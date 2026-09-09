"""Auth utilities — password hashing and JWT issuing/verification.

Uses the existing JWT_SECRET env var (already part of the platform's
secret contract in devops-app-secrets) — no new configuration required.
"""
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from .config import config
from .models import User

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer(auto_error=False)

JWT_ALGORITHM = "HS256"
JWT_EXPIRY = timedelta(hours=24)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(user_id: int, email: str) -> str:
    if not config.JWT_SECRET:
        # Fail loudly with a proper HTTP error rather than an unhandled
        # RuntimeError, which FastAPI serializes as a raw plaintext 500 —
        # that breaks any client doing res.json() on the response.
        raise HTTPException(
            status_code=500,
            detail="Authentication is not configured on this server (JWT_SECRET missing).",
        )

    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "email": email,
        "iat": now,
        "exp": now + JWT_EXPIRY,
    }
    return jwt.encode(payload, config.JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, config.JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.PyJWTError:
        return None


def make_get_current_user(db_session_dependency):
    """Builds a get_current_user dependency bound to the app's db_session.

    main.py calls this once with its own `db_session` generator so this
    module doesn't need to import from main.py (avoids a circular import)
    while still sharing the same request-scoped session.
    """
    def get_current_user(
        credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
        session: Session = Depends(db_session_dependency),
    ) -> User:
        if credentials is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")

        payload = decode_access_token(credentials.credentials)
        if payload is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")

        user = session.get(User, int(payload["sub"]))
        if user is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User no longer exists")

        return user

    return get_current_user