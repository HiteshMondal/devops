"""ORM models.

Kept minimal on purpose — two tables covering the two obvious portfolio
needs (things to showcase, and a way for visitors to reach). Add more
models here as the site grows.
"""
from datetime import UTC, datetime

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


class Project(Base):
    __tablename__ = "projects"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text, default="")
    link: Mapped[str] = mapped_column(String(500), default="")
    owner_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=True, default=None
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(UTC)
    )


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(UTC)
    )

class ContactMessage(Base):
    __tablename__ = "contact_messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    email: Mapped[str] = mapped_column(String(200))
    message: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=lambda: datetime.now(UTC)
    )

def utcnow_naive() -> datetime:
    """Naive UTC, matching how DateTime columns come back from SQLite/Postgres."""
    return datetime.now(UTC).replace(tzinfo=None)


class UserSecurity(Base):
    """1:1 with users. DB-backed lockout so security doesn't depend on Redis."""
    __tablename__ = "user_security"

    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    failed_logins: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    locked_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # Tokens issued before this moment are rejected (change password / logout-all)
    password_changed_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow_naive)


class UserProfile(Base):
    """1:1 personal info."""
    __tablename__ = "user_profiles"

    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    display_name: Mapped[str] = mapped_column(String(100), default="")
    headline: Mapped[str] = mapped_column(String(200), default="")
    bio: Mapped[str] = mapped_column(Text, default="")
    location: Mapped[str] = mapped_column(String(120), default="")
    website: Mapped[str] = mapped_column(String(500), default="")
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow_naive)


class UserInfoItem(Base):
    """1:N personal data (phones, addresses, socials, skills...)."""
    __tablename__ = "user_info_items"
    __table_args__ = (
        UniqueConstraint("user_id", "kind", "label", name="uq_info_user_kind_label"),
        CheckConstraint(
            "kind IN ('phone','address','social','education','skill','other')",
            name="ck_info_kind",
        ),
        CheckConstraint("length(value) > 0", name="ck_info_value_nonempty"),
        Index("ix_info_user_kind", "user_id", "kind"),   # B-Tree (default index type)
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    kind: Mapped[str] = mapped_column(String(20))
    label: Mapped[str] = mapped_column(String(100))
    value: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow_naive)
