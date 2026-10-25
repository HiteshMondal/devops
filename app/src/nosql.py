"""Optional Redis + MongoDB helpers.

Both are disabled unless REDIS_URL / MONGO_URL are set. Every call fails open:
if a database is down the app keeps working, and the failing backend is
skipped for 30s so requests don't pile up on timeouts.
"""
import logging
import os
import time
from datetime import UTC, datetime

logger = logging.getLogger("uvicorn.error")

REDIS_URL = os.environ.get("REDIS_URL", "")
MONGO_URL = os.environ.get("MONGO_URL", "")
MONGO_DB = os.environ.get("MONGO_DB", "devopsapp")
_COOLDOWN = 30

_redis = None
_redis_down_until = 0.0
_mongo = None
_mongo_indexed = False
_mongo_down_until = 0.0


def redis_enabled() -> bool:
    return bool(REDIS_URL)


def mongo_enabled() -> bool:
    return bool(MONGO_URL)


# Redis

def _get_redis():
    global _redis
    if not REDIS_URL or time.monotonic() < _redis_down_until:
        return None
    if _redis is None:
        import redis
        _redis = redis.Redis.from_url(
            REDIS_URL, decode_responses=True,
            socket_connect_timeout=3, socket_timeout=3,
            health_check_interval=30,
        )
    return _redis


def _redis_failed(exc):
    global _redis_down_until
    _redis_down_until = time.monotonic() + _COOLDOWN
    logger.warning("Redis unavailable (skipping for %ss): %s", _COOLDOWN, exc)


def revoke_token(jti: str, ttl_seconds: int) -> None:
    """Logout: blacklist a JWT id until the token would have expired anyway."""
    try:
        r = _get_redis()
        if r:
            r.setex(f"revoked:{jti}", ttl_seconds, "1")
    except Exception as exc:  # noqa: BLE001
        _redis_failed(exc)


def is_token_revoked(jti: str | None) -> bool:
    if not jti:
        return False
    try:
        r = _get_redis()
        return bool(r and r.exists(f"revoked:{jti}"))
    except Exception as exc:  # noqa: BLE001
        _redis_failed(exc)
        return False


def hit_rate_limit(key: str, limit: int, window: int) -> bool:
    """Count an attempt; True if the caller is now over the limit."""
    try:
        r = _get_redis()
        if not r:
            return False
        k = f"ratelimit:{key}"
        count = r.incr(k)
        if count == 1:
            r.expire(k, window)
        return count > limit
    except Exception as exc:  # noqa: BLE001
        _redis_failed(exc)
        return False


def reset_rate_limit(key: str) -> None:
    try:
        r = _get_redis()
        if r:
            r.delete(f"ratelimit:{key}")
    except Exception as exc:  # noqa: BLE001
        _redis_failed(exc)


def incr_page_views() -> None:
    try:
        r = _get_redis()
        if r:
            r.incr("stats:page_views")
    except Exception as exc:  # noqa: BLE001
        _redis_failed(exc)


def get_page_views() -> int | None:
    try:
        r = _get_redis()
        return int(r.get("stats:page_views") or 0) if r else None
    except Exception as exc:  # noqa: BLE001
        _redis_failed(exc)
        return None


# MongoDB

def _get_mongo():
    global _mongo, _mongo_indexed
    if not MONGO_URL or time.monotonic() < _mongo_down_until:
        return None
    if _mongo is None:
        from pymongo import MongoClient
        _mongo = MongoClient(
            MONGO_URL,
            serverSelectionTimeoutMS=3000,
            connectTimeoutMS=3000,
            socketTimeoutMS=5000,
            tz_aware=True,
        )[MONGO_DB]
    if not _mongo_indexed:
        _mongo.activity.create_index([("user_id", 1), ("created_at", -1)])
        _mongo_indexed = True
    return _mongo


def _mongo_failed(exc):
    global _mongo_down_until
    _mongo_down_until = time.monotonic() + _COOLDOWN
    logger.warning("MongoDB unavailable (skipping for %ss): %s", _COOLDOWN, exc)


def log_activity(user_id: int, action: str, **details) -> None:
    try:
        db = _get_mongo()
        if db is not None:
            db.activity.insert_one({
                "user_id": user_id,
                "action": action,
                "details": details,  # free-form: the point of a document store
                "created_at": datetime.now(UTC),
            })
    except Exception as exc:  # noqa: BLE001
        _mongo_failed(exc)


def recent_activity(user_id: int, limit: int = 20) -> list[dict]:
    try:
        db = _get_mongo()
        if db is None:
            return []
        cursor = db.activity.find({"user_id": user_id}).sort("created_at", -1).limit(limit)
        return [
            {"action": d["action"], "details": d.get("details", {}),
             "created_at": d["created_at"].isoformat()}
            for d in cursor
        ]
    except Exception as exc:  # noqa: BLE001
        _mongo_failed(exc)
        return []
