"""Application entrypoint — Personal/Portfolio site.

Run with: uvicorn src.main:app --host 0.0.0.0 --port $APP_PORT
(this is exactly what the Dockerfile's CMD does).

Structure kept intentionally small:
  config.py    — env-driven settings (unchanged contract with the platform)
  database.py  — SQLite engine/session (swap for Postgres later if needed)
  models.py    — Project, ContactMessage
  static/app.js — the entire frontend (HTML/CSS generated client-side)
"""
import logging
import os
from pathlib import Path
from typing import Annotated

import httpx
from fastapi import BackgroundTasks, Depends, FastAPI
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, EmailStr, field_validator
from sqlalchemy import text
from sqlalchemy.orm import Session

from .config import config
from .database import get_session, init_db

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError

from .auth import create_access_token, hash_password, make_get_current_user, verify_password
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
def ready(session: DBSession):
    """Readiness probe — deep-checks the database connection so
    Kubernetes stops routing traffic here if the DB is unreachable."""
    checks = {}
    overall_ok = True

    try:
        session.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as exc:  # noqa: BLE001 — any failure means "not ready"
        checks["database"] = "unreachable"
        overall_ok = False
        logger.warning("Readiness DB check failed: %s", exc)

    status_code = 200 if overall_ok else 503
    body = {"status": "ready" if overall_ok else "not_ready", "checks": checks}
    return JSONResponse(status_code=status_code, content=body)


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


# Projects

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


class ProjectIn(BaseModel):
    title: str
    description: str = ""
    link: str = ""


@app.get("/api/v1/projects")
def list_projects(session: DBSession):
    projects = session.query(Project).order_by(Project.created_at.desc()).all()
    return [
        {"id": p.id, "title": p.title, "description": p.description, "link": p.link}
        for p in projects
    ]


@app.post("/api/v1/projects")
def create_project(body: ProjectIn, session: DBSession):
    project = Project(title=body.title, description=body.description, link=body.link)
    session.add(project)
    session.flush()
    return {"id": project.id}


# Contact

class ContactIn(BaseModel):
    name: str
    email: EmailStr
    message: str


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