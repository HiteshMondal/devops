"""Auth utilities — password hashing and JWT issuing/verification.

Uses the existing JWT_SECRET env var (already part of the platform's
secret contract in devops-app-secrets) — no new configuration required.
"""
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from passlib.context import CryptContext
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import nosql
from .config import config
from .models import User, UserSecurity

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer(auto_error=False)

JWT_ALGORITHM = "HS256"
JWT_EXPIRY = timedelta(hours=24)
MAX_FAILED_LOGINS = 10
LOCKOUT_FOR = timedelta(minutes=15)
# Verified when the email doesn't exist, so response time doesn't reveal valid accounts
DUMMY_HASH = pwd_context.hash("timing-equalizer-not-a-real-password")


def client_ip(request: Request) -> str:
    # Last X-Forwarded-For hop is the one appended by our own ingress; the
    # leftmost entries can be forged by the caller.
    xff = request.headers.get("x-forwarded-for", "")
    if xff:
        return xff.split(",")[-1].strip()
    return request.client.host if request.client else "unknown"


def is_admin_email(email: str) -> bool:
    admins = {e.strip().lower() for e in config.ADMIN_EMAILS.split(",") if e.strip()}
    return (not admins) or email.lower() in admins   # unset = legacy behaviour


def get_or_create_security(session: Session, user: User) -> UserSecurity:
    """Row-locks the counter row; lazily creates it for pre-existing users."""
    sec = session.get(UserSecurity, user.id, with_for_update=True)
    if sec is None:
        try:
            with session.begin_nested():
                # created_at, so old users' existing tokens stay valid
                session.add(UserSecurity(user_id=user.id, password_changed_at=user.created_at))
        except IntegrityError:
            pass  # another request created it first
        sec = session.get(UserSecurity, user.id, with_for_update=True)
    return sec

def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(user_id: int, email: str) -> str:
    if not config.JWT_SECRET:
        raise HTTPException(
            status_code=500,
            detail="Authentication is not configured on this server (JWT_SECRET missing).",
        )

    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "email": email,
        "jti": uuid.uuid4().hex,
        "iat": now,
        "exp": now + JWT_EXPIRY,
    }
    return jwt.encode(payload, config.JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> dict | None:
    try:
        return jwt.decode(
            token, config.JWT_SECRET, algorithms=[JWT_ALGORITHM],
            options={"require": ["exp", "sub", "jti", "iat"]},
        )
    except jwt.PyJWTError:
        return None


def make_get_current_user(db_session_dependency):
    def get_current_user(
        credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
        session: Session = Depends(db_session_dependency),
    ) -> User:
        if credentials is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")

        payload = decode_access_token(credentials.credentials)
        if payload is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")
        if nosql.is_token_revoked(payload.get("jti")):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has been revoked")
        try:
            user_id = int(payload["sub"])
        except (KeyError, TypeError, ValueError):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")
        user = session.get(User, user_id)
        if user is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User no longer exists")

        sec = session.get(UserSecurity, user.id)
        if sec is not None:
            changed = int(sec.password_changed_at.replace(tzinfo=UTC).timestamp())
            if int(payload.get("iat", 0)) < changed:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                                    detail="Session expired — please log in again")
        return user

    return get_current_user