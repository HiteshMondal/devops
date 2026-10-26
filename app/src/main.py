"""Application entrypoint — Personal/Portfolio site.

Run with: uvicorn src.main:app --host 0.0.0.0 --port $APP_PORT
(this is exactly what the Dockerfile's CMD does).

"""
import logging
import os
import time
from pathlib import Path
from typing import Annotated, Literal

import httpx
from fastapi import BackgroundTasks, Depends, FastAPI, HTTPException, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.security import HTTPAuthorizationCredentials
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, EmailStr, Field, StringConstraints, field_validator
from sqlalchemy import func, text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from . import nosql
from .auth import (
    DUMMY_HASH,
    LOCKOUT_FOR,
    MAX_FAILED_LOGINS,
    bearer_scheme,
    client_ip,
    create_access_token,
    decode_access_token,
    get_or_create_security,
    hash_password,
    is_admin_email,
    make_get_current_user,
    verify_password,
)
from .circuit_breaker import CircuitOpenError
from .config import config
from .database import get_session, init_db
from .metrics import PrometheusMiddleware, metrics_response
from .middleware import RequestContextLogMiddleware
from .models import (
    ContactMessage,
    Project,
    User,
    UserInfoItem,
    UserProfile,
    UserSecurity,
    utcnow_naive,
)

logger = logging.getLogger("uvicorn.error")

app = FastAPI(title=config.APP_NAME)
app.add_middleware(PrometheusMiddleware)
app.add_middleware(RequestContextLogMiddleware)

@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "same-origin")
    if request.url.path not in ("/docs", "/redoc"):   # Swagger loads scripts from a CDN
        response.headers.setdefault(
            "Content-Security-Policy",
            "default-src 'self'; style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data:; frame-ancestors 'none'",
        )
    return response

STATIC_DIR = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.on_event("startup")
def on_startup():
    init_db()
    logger.info("NoSQL status: %s", nosql.health())

def db_session():
    with get_session() as session:
        yield session


DBSession = Annotated[Session, Depends(db_session)]
CurrentUser = Annotated[User, Depends(make_get_current_user(db_session))]

def require_admin(current_user: CurrentUser) -> User:
    if not is_admin_email(current_user.email):
        raise HTTPException(status_code=403, detail="Admin access required")
    return current_user


AdminUser = Annotated[User, Depends(require_admin)]

# Shared pagination query params. Capped at 100 per page so a caller can't
# force the DB to load an unbounded number of rows in one request.
PageParam = Annotated[int, Query(ge=1, description="1-indexed page number")]
PageSizeParam = Annotated[int, Query(ge=1, le=100, description="Items per page (max 100)")]


# Frontend

@app.get("/", response_class=HTMLResponse)
def index():
    nosql.incr_page_views()
    """Minimal shell — app.js builds the entire page client-side."""
    return """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Portfolio</title>
</head>
<body>
  <script src="/static/app.js"></script>
</body>
</html>"""


# Health
# Kept identical in shape to the previous app so probes/monitoring configs
# already in the platform keep working unmodified.

@app.get("/health")
@app.get("/api/v1/health")
def health():
    """Liveness probe — is the process up? Deliberately no dependency
    checks here so a slow/down DB doesn't take down liveness (which
    would cause Kubernetes to restart a pod that's otherwise fine)."""
    return {
        "status": "ok",
        "app": config.APP_NAME,
        "env": config.APP_ENV,
    }


@app.get("/ready")
@app.get("/api/v1/ready")
def readiness():
    """Readiness probe — confirms the application can reach the database.

    Both /ready and /api/v1/ready are supported because Kubernetes,
    monitoring, tests, and existing clients use the versioned endpoint.
    """
    checks = {
        "database": "unreachable",
    }
    overall_ok = False

    try:
        with get_session() as session:
            session.execute(text("SELECT 1"))

        checks["database"] = "ok"
        overall_ok = True

    except (SQLAlchemyError, RuntimeError) as exc:
        checks["database"] = "unreachable"
        logger.warning("Readiness DB check failed: %s", exc)

    status_code = 200 if overall_ok else 503

    return JSONResponse(
        status_code=status_code,
        content={
            "status": "ready" if overall_ok else "not_ready",
            "checks": checks,
        },
    )


@app.get("/config")
@app.get("/api/v1/config")
def get_config():
    """Non-sensitive runtime configuration (secrets are never returned)."""
    return {
        "app_name": config.APP_NAME,
        "app_env": config.APP_ENV,
        "app_port": config.APP_PORT,
        "log_level": config.LOG_LEVEL,
    }

@app.get("/metrics")
def metrics():
    return metrics_response()


# Auth

def validate_new_password(v: str) -> str:
    if len(v) < 8:
        raise ValueError("Password must be at least 8 characters")
    if len(v.encode("utf-8")) > 72:
        raise ValueError("Password must be 72 bytes or fewer")
    if not (any(c.isalpha() for c in v) and any(c.isdigit() for c in v)):
        raise ValueError("Password must contain at least one letter and one number")
    return v


class SignupIn(BaseModel):
    email: EmailStr
    password: str

    @field_validator("password")
    @classmethod
    def password_rules(cls, v: str) -> str:
        return validate_new_password(v)


class LoginIn(BaseModel):
    email: EmailStr
    password: str

class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def _rules(cls, v: str) -> str:
        return validate_new_password(v)
 
@app.post("/api/v1/auth/signup")
def signup(body: SignupIn, request: Request, session: DBSession):
    if nosql.hit_rate_limit(f"signup-ip:{client_ip(request)}", limit=10, window=3600):
        raise HTTPException(status_code=429, detail="Too many sign-ups from this address. Try later.")

    email = body.email.lower()
    if session.query(User).filter(func.lower(User.email) == email).first():
        raise HTTPException(status_code=409, detail="Email already registered")

    user = User(email=email, hashed_password=hash_password(body.password))
    session.add(user)
    try:
        session.flush()
        # Atomic: user + security + profile rows commit together or not at all
        session.add(UserSecurity(user_id=user.id, password_changed_at=utcnow_naive()))
        session.add(UserProfile(user_id=user.id, display_name=email.split("@")[0]))
        session.flush()
    except IntegrityError:
        session.rollback()
        raise HTTPException(status_code=409, detail="Email already registered")

    user_id = user.id
    session.commit()   # durable BEFORE a token is handed out
    nosql.log_activity(user_id, "signup")
    return {"access_token": create_access_token(user_id, email), "token_type": "bearer"}


@app.post("/api/v1/auth/login")
def login(body: LoginIn, request: Request, session: DBSession):
    email = body.email.lower()
    if nosql.hit_rate_limit(f"login-ip:{client_ip(request)}", limit=30, window=900):
        raise HTTPException(status_code=429, detail="Too many attempts. Try again in 15 minutes.")
    rl_key = f"login:{email}"
    if nosql.hit_rate_limit(rl_key, limit=5, window=900):
        raise HTTPException(status_code=429, detail="Too many attempts. Try again in 15 minutes.")

    user = session.query(User).filter(func.lower(User.email) == email).first()
    sec = get_or_create_security(session, user) if user else None
    now = utcnow_naive()
    if sec and sec.locked_until and sec.locked_until > now:
        raise HTTPException(status_code=429, detail="Account temporarily locked. Try again later.")

    password_ok = verify_password(body.password, user.hashed_password if user else DUMMY_HASH)
    if user is None or not password_ok:
        if sec:
            sec.failed_logins += 1
            if sec.failed_logins >= MAX_FAILED_LOGINS:   # DB backstop for when Redis is down
                sec.locked_until = now + LOCKOUT_FOR
                sec.failed_logins = 0
            # MUST commit before raising: get_session() rolls back on any exception,
            # which would silently discard the counter.
            session.commit()
        raise HTTPException(status_code=401, detail="Invalid email or password")

    sec.failed_logins = 0
    sec.locked_until = None
    sec.last_login_at = now
    nosql.reset_rate_limit(rl_key)
    nosql.log_activity(user.id, "login")
    return {"access_token": create_access_token(user.id, user.email), "token_type": "bearer"}


@app.post("/api/v1/auth/logout", status_code=204)
def logout(
    current_user: CurrentUser,
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
):
    payload = decode_access_token(credentials.credentials) or {}
    if payload.get("jti") and payload.get("exp"):
        nosql.revoke_token(payload["jti"], max(int(payload["exp"] - time.time()), 1))
    nosql.log_activity(current_user.id, "logout")


@app.get("/api/v1/auth/me")
def me(current_user: CurrentUser):
    return {"id": current_user.id, "email": current_user.email,
            "is_admin": is_admin_email(current_user.email)}

@app.post("/api/v1/auth/change-password")
def change_password(body: ChangePasswordIn, current_user: CurrentUser, session: DBSession):
    if not verify_password(body.current_password, current_user.hashed_password):
        raise HTTPException(status_code=403, detail="Current password is incorrect")
    current_user.hashed_password = hash_password(body.new_password)
    get_or_create_security(session, current_user).password_changed_at = utcnow_naive()
    uid, email = current_user.id, current_user.email
    session.commit()   # every older token (all devices) is now invalid
    nosql.log_activity(uid, "password_changed")
    return {"access_token": create_access_token(uid, email), "token_type": "bearer"}


@app.post("/api/v1/auth/logout-all", status_code=204)
def logout_all(current_user: CurrentUser, session: DBSession):
    get_or_create_security(session, current_user).password_changed_at = utcnow_naive()
    nosql.log_activity(current_user.id, "logout_all")


class DeleteAccountIn(BaseModel):
    password: str


@app.delete("/api/v1/me", status_code=204)
def delete_account(body: DeleteAccountIn, current_user: CurrentUser, session: DBSession):
    if not verify_password(body.password, current_user.hashed_password):
        raise HTTPException(status_code=403, detail="Password is incorrect")
    uid = current_user.id
    # One transaction across 5 tables. Explicit deletes (not relying on ON DELETE
    # CASCADE) so it behaves the same on SQLite, where FKs are off by default.
    session.query(Project).filter(Project.owner_id == uid).delete(synchronize_session=False)
    session.query(UserInfoItem).filter(UserInfoItem.user_id == uid).delete(synchronize_session=False)
    session.query(UserProfile).filter(UserProfile.user_id == uid).delete(synchronize_session=False)
    session.query(UserSecurity).filter(UserSecurity.user_id == uid).delete(synchronize_session=False)
    session.query(User).filter(User.id == uid).delete(synchronize_session=False)
    session.commit()
    nosql.cache_bump()
    nosql.log_activity(uid, "account_deleted")


# Projects

class ProjectIn(BaseModel):
    title: str
    description: str = ""
    link: str = ""


class ProjectUpdateIn(BaseModel):
    """All fields optional — PATCH-style partial update."""
    title: str | None = None
    description: str | None = None
    link: str | None = None


def _project_out(p: Project) -> dict:
    return {
        "id": p.id,
        "title": p.title,
        "description": p.description,
        "link": p.link,
        "owner_id": p.owner_id,
        "created_at": p.created_at.isoformat(),
    }


def _get_owned_project_or_404(session: Session, project_id: int, current_user: User) -> Project:
    project = session.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    if project.owner_id != current_user.id:
        # 404 rather than 403 so we don't leak the existence of other
        # users' projects to someone who doesn't own them.
        raise HTTPException(status_code=404, detail="Project not found")
    return project


@app.get("/api/v1/projects")
def list_projects(
    session: DBSession,
    page: PageParam = 1,
    page_size: PageSizeParam = 20,
):
    """Public, paginated project listing."""
    total = session.query(func.count(Project.id)).scalar() or 0
    projects = (
        session.query(Project)
        .order_by(Project.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return {
        "items": [_project_out(p) for p in projects],
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": (total + page_size - 1) // page_size if page_size else 0,
    }


@app.get("/api/v1/projects/mine")
def list_my_projects(
    current_user: CurrentUser,
    session: DBSession,
    page: PageParam = 1,
    page_size: PageSizeParam = 20,
):

    query = session.query(Project).filter(Project.owner_id == current_user.id)
    total = query.with_entities(func.count(Project.id)).scalar() or 0
    projects = (
        query.order_by(Project.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return {
        "items": [_project_out(p) for p in projects],
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": (total + page_size - 1) // page_size if page_size else 0,
    }


def _like_prefix(term: str) -> str:
    """Escape LIKE wildcards so user input matches literally, then make it a prefix."""
    return term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


@app.get("/api/v1/projects/search")
def search_projects(
    session: DBSession,
    q: Annotated[str, Query(min_length=1, max_length=100)],
    page: PageParam = 1,
    page_size: PageSizeParam = 20,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
):
    """Case-insensitive title-prefix search, served by the B-Tree on lower(title)."""
    term = q.strip().lower()
    if not term:
        raise HTTPException(status_code=422, detail="Search term is empty")

    cache_key = f"search:{nosql.cache_version()}:{page}:{page_size}:{term}"
    cached = nosql.cache_get(cache_key)
    if cached is not None:
        return cached

    query = session.query(Project).filter(
        func.lower(Project.title).like(_like_prefix(term), escape="\\")
    )
    total = query.with_entities(func.count(Project.id)).scalar() or 0
    rows = (
        query.order_by(func.lower(Project.title), Project.id)
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    result = {
        "items": [_project_out(p) for p in rows],
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": (total + page_size - 1) // page_size,
    }
    nosql.cache_set(cache_key, result, ttl=60)

    if page == 1:   # analytics event -> Atlas `search_events`
        payload = decode_access_token(credentials.credentials) if credentials else None
        nosql.log_search(int(payload["sub"]) if payload else None, term, total)
    return result


@app.get("/api/v1/projects/{project_id}")
def get_project(project_id: int, session: DBSession):
    project = session.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return _project_out(project)


@app.post("/api/v1/projects")
def create_project(body: ProjectIn, current_user: CurrentUser, session: DBSession):
    project = Project(
        title=body.title,
        description=body.description,
        link=body.link,
        owner_id=current_user.id,
    )
    session.add(project)
    session.flush()
    session.commit()
    nosql.cache_bump()
    nosql.log_activity(current_user.id, "project_created", project_id=project.id, title=project.title)
    return _project_out(project)


@app.patch("/api/v1/projects/{project_id}")
def update_project(
    project_id: int,
    body: ProjectUpdateIn,
    current_user: CurrentUser,
    session: DBSession,
):
    project = _get_owned_project_or_404(session, project_id, current_user)

    if body.title is not None:
        project.title = body.title
    if body.description is not None:
        project.description = body.description
    if body.link is not None:
        project.link = body.link

    session.flush()
    session.commit()
    nosql.cache_bump()
    nosql.log_activity(current_user.id, "project_updated", project_id=project.id)
    return _project_out(project)


@app.delete("/api/v1/projects/{project_id}", status_code=204)
def delete_project(project_id: int, current_user: CurrentUser, session: DBSession):
    project = _get_owned_project_or_404(session, project_id, current_user)
    nosql.log_activity(current_user.id, "project_deleted", project_id=project.id, title=project.title)
    session.delete(project)
    session.flush()
    session.commit()
    nosql.cache_bump()

@app.get("/api/v1/stats")
def stats():
    return {
        "page_views": nosql.get_page_views(),
        "redis_enabled": nosql.redis_enabled(),
        "mongo_enabled": nosql.mongo_enabled(),
    }


@app.get("/api/v1/activity")
def my_activity(
    current_user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
):
    return {"items": nosql.recent_activity(current_user.id, limit)}

# Contact

class ContactIn(BaseModel):
    name: str
    email: EmailStr
    message: str


def _contact_out(c: ContactMessage) -> dict:
    return {
        "id": c.id,
        "name": c.name,
        "email": c.email,
        "message": c.message,
        "created_at": c.created_at.isoformat(),
    }


def _notify_contact_submission(name: str, email: str, message: str) -> None:
    webhook_url = os.environ.get("CONTACT_WEBHOOK_URL", "")
    if not webhook_url:
        return

    payload = {
        "content": f"New contact message from {name} <{email}>:\n{message}",
    }

    try:
        httpx.post(webhook_url, json=payload, timeout=5.0)
    except Exception as exc:  # noqa: BLE001 — notification failures must not break the request
        logger.warning("Contact notification webhook failed: %s", exc)


@app.post("/api/v1/contact")
def submit_contact(
    body: ContactIn,
    background_tasks: BackgroundTasks,
    session: DBSession,
):
    entry = ContactMessage(name=body.name, email=body.email, message=body.message)
    session.add(entry)
    session.flush()

    background_tasks.add_task(
        _notify_contact_submission, body.name, body.email, body.message
    )

    return {"status": "received", "id": entry.id}


@app.get("/api/v1/contact")
def list_contact_messages(
    _admin: AdminUser,
    session: DBSession,
    page: PageParam = 1,
    page_size: PageSizeParam = 20,
):

    total = session.query(func.count(ContactMessage.id)).scalar() or 0
    messages = (
        session.query(ContactMessage)
        .order_by(ContactMessage.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return {
        "items": [_contact_out(c) for c in messages],
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": (total + page_size - 1) // page_size if page_size else 0,
    }


@app.exception_handler(CircuitOpenError)
async def circuit_open_handler(request, exc):
    return JSONResponse(
        status_code=503,
        content={"status": "unavailable", "detail": str(exc)},
    )

InfoKind = Literal["phone", "address", "social", "education", "skill", "other"]
Str100 = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
Str1000 = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)]


class ProfileIn(BaseModel):
    display_name: str | None = Field(default=None, max_length=100)
    headline: str | None = Field(default=None, max_length=200)
    bio: str | None = Field(default=None, max_length=2000)
    location: str | None = Field(default=None, max_length=120)
    website: str | None = Field(default=None, max_length=500)

    @field_validator("website")
    @classmethod
    def _website(cls, v):
        if v and not v.lower().startswith(("http://", "https://")):
            raise ValueError("Website must start with http:// or https://")
        return v


class InfoItemIn(BaseModel):
    kind: InfoKind
    label: Str100
    value: Str1000


def _profile_out(p: UserProfile) -> dict:
    return {"display_name": p.display_name, "headline": p.headline, "bio": p.bio,
            "location": p.location, "website": p.website, "updated_at": p.updated_at.isoformat()}


def _info_out(i: UserInfoItem) -> dict:
    return {"id": i.id, "kind": i.kind, "label": i.label, "value": i.value,
            "created_at": i.created_at.isoformat()}


def _get_or_create_profile(session: Session, user: User) -> UserProfile:
    p = session.get(UserProfile, user.id)
    if p is None:
        try:
            with session.begin_nested():
                session.add(UserProfile(user_id=user.id, display_name=user.email.split("@")[0]))
        except IntegrityError:
            pass
        p = session.get(UserProfile, user.id)
    return p


@app.get("/api/v1/me/profile")
def get_my_profile(current_user: CurrentUser, session: DBSession):
    p = _get_or_create_profile(session, current_user)
    items = (
        session.query(UserInfoItem)
        .filter(UserInfoItem.user_id == current_user.id)
        .order_by(UserInfoItem.kind, UserInfoItem.label)   # served by ix_info_user_kind
        .all()
    )
    return {"profile": _profile_out(p), "items": [_info_out(i) for i in items]}


@app.patch("/api/v1/me/profile")
def update_my_profile(body: ProfileIn, current_user: CurrentUser, session: DBSession):
    p = _get_or_create_profile(session, current_user)
    changes = body.model_dump(exclude_unset=True)
    for field, value in changes.items():
        setattr(p, field, value or "")
    p.updated_at = utcnow_naive()
    session.flush()
    nosql.log_activity(current_user.id, "profile_updated", fields=sorted(changes))
    return _profile_out(p)


@app.post("/api/v1/me/info", status_code=201)
def add_info_item(body: InfoItemIn, current_user: CurrentUser, session: DBSession):
    item = UserInfoItem(user_id=current_user.id, kind=body.kind, label=body.label, value=body.value)
    session.add(item)
    try:
        session.flush()
    except IntegrityError:   # UNIQUE(user_id, kind, label)
        session.rollback()
        raise HTTPException(status_code=409, detail="You already have an item with that kind and label")
    nosql.log_activity(current_user.id, "info_added", kind=body.kind)
    return _info_out(item)


@app.delete("/api/v1/me/info/{item_id}", status_code=204)
def delete_info_item(item_id: int, current_user: CurrentUser, session: DBSession):
    deleted = (
        session.query(UserInfoItem)
        .filter(UserInfoItem.id == item_id, UserInfoItem.user_id == current_user.id)
        .delete(synchronize_session=False)
    )
    if not deleted:   # 404 (not 403), same policy as projects
        raise HTTPException(status_code=404, detail="Item not found")
    nosql.log_activity(current_user.id, "info_deleted", item_id=item_id)
