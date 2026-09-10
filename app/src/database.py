"""Database engine & session setup.

Tries Postgres first (built from the existing DB_* env vars — same
contract as before, no new variables). If Postgres is unreachable at
startup (host down, not yet provisioned, credentials missing, etc.), we
fall back to the original on-disk SQLite file automatically, so any
existing deployment that hasn't provisioned Postgres yet keeps working
unmodified.

A clear log line always states which backend ended up active — check
`uvicorn`/pod logs to confirm.
"""
import logging
import os
from contextlib import contextmanager

from sqlalchemy import create_engine, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import config

logger = logging.getLogger("uvicorn.error")

SQLITE_URL = f"sqlite:///{config.DB_SQLITE_PATH}"


def _build_postgres_url() -> str | None:
    """Build a Postgres DSN from existing DB_* vars, or None if unset."""
    if not config.DB_HOST or config.DB_HOST == "localhost":
        # "localhost" is the historical default when nobody set DB_HOST —
        # treat it the same as "not configured" so local/dev without a
        # Postgres instance falls back to SQLite instead of trying (and
        # failing) to reach a local Postgres that doesn't exist.
        return None
    from urllib.parse import quote_plus
    user = quote_plus(config.DB_USERNAME)
    pwd = quote_plus(config.DB_PASSWORD)
    return (
        f"postgresql+psycopg://{user}:{pwd}"
        f"@{config.DB_HOST}:{config.DB_PORT}/{config.DB_NAME}"
    )


def _try_postgres_engine():
    url = _build_postgres_url()
    if not url:
        return None

    try:
        engine = create_engine(url, pool_pre_ping=True, connect_args={"connect_timeout": 3})
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return engine
    except Exception as exc:  # noqa: BLE001 — any failure means "not available"
        logger.warning(
            "Postgres unreachable at %s:%s/%s (%s) — falling back to SQLite",
            config.DB_HOST, config.DB_PORT, config.DB_NAME, exc,
        )
        return None


def _build_engine():
    pg_engine = _try_postgres_engine()
    if pg_engine is not None:
        logger.info("Database backend: Postgres (%s:%s/%s)", config.DB_HOST, config.DB_PORT, config.DB_NAME)
        return pg_engine

    dirname = os.path.dirname(config.DB_SQLITE_PATH)
    if dirname:
        try:
            os.makedirs(dirname, exist_ok=True)
        except PermissionError:
            logger.warning(
                "Cannot create SQLite directory %s (no permission) — "
                "falling back to in-memory SQLite", dirname,
            )
            return create_engine(
                "sqlite:///:memory:",
                connect_args={"check_same_thread": False},
            )
    logger.info("Database backend: SQLite (%s)", config.DB_SQLITE_PATH)
    return create_engine(SQLITE_URL, connect_args={"check_same_thread": False})


engine = _build_engine()
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def init_db() -> None:
    from . import models  # noqa: F401 — ensure models are registered
    Base.metadata.create_all(bind=engine)


@contextmanager
def get_session():
    session: Session = SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()