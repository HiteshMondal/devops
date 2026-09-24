"""Shared pytest fixtures.

Tests never touch the real DB_SQLITE_PATH file or any external Postgres —
they run against an isolated in-memory SQLite database, so they pass the
same way whether run locally, in GitHub Actions, in Jenkins, or in GitLab
CI's Postgres-service job. No .env values are required for tests to run.
"""
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.database import Base
from src.main import app, db_session
from src.config import config


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setattr(config, "JWT_SECRET", "test-only-jwt-secret")
    # Use a shared in-memory SQLite DB (StaticPool keeps the same connection
    # alive across the pool so ":memory:" isn't wiped between uses).
    from sqlalchemy.pool import StaticPool

    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    Base.metadata.create_all(bind=engine)

    # Prevent the real startup hook from touching the file-based production
    # engine/DB during tests — table creation for tests happens above,
    # against the isolated in-memory engine instead.
    monkeypatch.setattr("src.main.init_db", lambda: None)

    def override_db_session():
        session = TestingSessionLocal()
        try:
            yield session
            session.commit()
        except Exception:
            session.rollback()
            raise
        finally:
            session.close()

    app.dependency_overrides[db_session] = override_db_session

    with TestClient(app) as test_client:
        yield test_client

    app.dependency_overrides.clear()