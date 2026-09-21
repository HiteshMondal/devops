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
import time
from contextlib import contextmanager

from sqlalchemy import create_engine, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.exc import InterfaceError, OperationalError

from .config import config

from .circuit_breaker import CircuitOpenError, CircuitState, db_circuit_breaker

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


def _try_postgres_engine(retries: int = 5, base_delay: float = 2.0):
    """Attempt to connect to Postgres with exponential backoff.

    RDS can take longer than a single short timeout to accept connections
    (cold start, post-failover, brief network blips), so a single 3s
    attempt was too eager to give up. This retries before conceding.
    """
    url = _build_postgres_url()
    if not url:
        return None

    last_exc = None
    for attempt in range(1, retries + 1):
        try:
            engine = create_engine(url, pool_pre_ping=True, connect_args={"connect_timeout": 5})
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            if attempt > 1:
                logger.info("Postgres became reachable on attempt %d/%d", attempt, retries)
            return engine
        except Exception as exc:  # noqa: BLE001 — any failure means "not yet available"
            last_exc = exc
            if attempt < retries:
                delay = base_delay * (2 ** (attempt - 1))
                logger.warning(
                    "Postgres unreachable at %s:%s/%s (attempt %d/%d): %s — retrying in %.1fs",
                    config.DB_HOST, config.DB_PORT, config.DB_NAME, attempt, retries, exc, delay,
                )
                time.sleep(delay)

    logger.error(
        "Postgres unreachable at %s:%s/%s after %d attempts: %s",
        config.DB_HOST, config.DB_PORT, config.DB_NAME, retries, last_exc,
    )
    return None


def _build_engine():
    pg_engine = _try_postgres_engine()
    if pg_engine is not None:
        logger.info("Database backend: Postgres (%s:%s/%s)", config.DB_HOST, config.DB_PORT, config.DB_NAME)
        return pg_engine

    if config.APP_ENV == "production":
        raise RuntimeError(
            f"Postgres unreachable at {config.DB_HOST}:{config.DB_PORT}/{config.DB_NAME} "
            "in production — refusing to silently fall back to SQLite. "
            "Check RDS status, security groups, and credentials."
        )

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
    if db_circuit_breaker.state == CircuitState.OPEN:
        raise CircuitOpenError(
            "Database circuit breaker is open — refusing new session"
        )

    session: Session = SessionLocal()
    try:
        yield session
        session.commit()
    except (OperationalError, InterfaceError):
        # Connectivity failures only: this is what the breaker protects against.
        session.rollback()
        db_circuit_breaker._record_failure()
        raise
    except Exception:
        session.rollback()
        raise
    else:
        db_circuit_breaker._record_success()
    finally:
        session.close()