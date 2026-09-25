"""Application entrypoint — Personal/Portfolio site.

Run with: uvicorn src.main:app --host 0.0.0.0 --port $APP_PORT
(this is exactly what the Dockerfile's CMD does).

"""
import logging
import os
from pathlib import Path
from typing import Annotated

import httpx
from fastapi import BackgroundTasks, Depends, FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, EmailStr, field_validator

from sqlalchemy import func, text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from .auth import (
    create_access_token,
    hash_password,
    make_get_current_user,
    verify_password,
)
from .circuit_breaker import CircuitOpenError
from .config import config
from .database import get_session, init_db
from .metrics import PrometheusMiddleware, metrics_response
from .middleware import RequestContextLogMiddleware
from .models import ContactMessage, Project, User

logger = logging.getLogger("uvicorn.error")

app = FastAPI(title=config.APP_NAME)
app.add_middleware(PrometheusMiddleware)
app.add_middleware(RequestContextLogMiddleware)

STATIC_DIR = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.on_event("startup")
def on_startup():
    init_db()


def db_session():
    with get_session() as session:
        yield session


DBSession = Annotated[Session, Depends(db_session)]
CurrentUser = Annotated[User, Depends(make_get_current_user(db_session))]

# Shared pagination query params. Capped at 100 per page so a caller can't
# force the DB to load an unbounded number of rows in one request.
PageParam = Annotated[int, Query(ge=1, description="1-indexed page number")]
PageSizeParam = Annotated[int, Query(ge=1, le=100, description="Items per page (max 100)")]


# Frontend

@app.get("/", response_class=HTMLResponse)
def index():
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

class SignupIn(BaseModel):
    email: EmailStr
    password: str

    @field_validator("password")
    @classmethod
    def password_within_bcrypt_limit(cls, v: str) -> str:
        if len(v.encode("utf-8")) > 72:
            raise ValueError("Password must be 72 bytes or fewer")
        return v


class LoginIn(BaseModel):
    email: EmailStr
    password: str
 
 
@app.post("/api/v1/auth/signup")
def signup(body: SignupIn, session: DBSession):
    user = User(email=body.email, hashed_password=hash_password(body.password))
    session.add(user)
    try:
        session.flush()
    except IntegrityError:
        session.rollback()
        raise HTTPException(status_code=409, detail="Email already registered")
 
    token = create_access_token(user.id, user.email)
    return {"access_token": token, "token_type": "bearer"}
 
 
@app.post("/api/v1/auth/login")
def login(body: LoginIn, session: DBSession):
    user = session.query(User).filter(User.email == body.email).first()
    if user is None or not verify_password(body.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")
 
    token = create_access_token(user.id, user.email)
    return {"access_token": token, "token_type": "bearer"}
 
 
@app.get("/api/v1/auth/me")
def me(current_user: CurrentUser):
    return {"id": current_user.id, "email": current_user.email}


# Projects
#
# Full CRUD. Listing is public (portfolio visitors need to see projects
# without logging in) and paginated. Create/update/delete require auth,
# and update/delete are restricted to the project's own owner — this is
# the "My projects" ownership feature.

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
    """Projects owned by the logged-in user. Must be declared before the
    /{project_id} route below so FastAPI doesn't try to parse "mine" as
    an int path param."""
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
    return _project_out(project)


@app.delete("/api/v1/projects/{project_id}", status_code=204)
def delete_project(project_id: int, current_user: CurrentUser, session: DBSession):
    project = _get_owned_project_or_404(session, project_id, current_user)
    session.delete(project)
    session.flush()


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
    """Best-effort fire-and-forget notification for a new contact message.

    Controlled entirely by the optional CONTACT_WEBHOOK_URL env var (not
    part of the existing .env contract — add it yourself if you want this
    active). If it's unset, this is a no-op, so behavior is unchanged for
    anyone who hasn't opted in. Any failure here is only logged; it must
    never affect the API response already sent to the client.
    """
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
    current_user: CurrentUser,
    session: DBSession,
    page: PageParam = 1,
    page_size: PageSizeParam = 20,
):
    """Admin-only listing of submitted contact messages.

    Any authenticated user can read this — there's no separate admin role
    in this app yet, so "authenticated" is the only bar. Add a role check
    here if you introduce one later.
    """
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
