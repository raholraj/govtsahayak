"""In-memory session store. HARD GATE: can_submit only after explicit HAAN."""
from __future__ import annotations
import uuid
from typing import Any, Optional
from models.schemas import AgentStatus

_SESSIONS: dict[str, dict[str, Any]] = {}


def create_session(service_id: str, fields: dict, portal_url: str) -> str:
    sid = str(uuid.uuid4())
    _SESSIONS[sid] = {
        "session_id": sid,
        "service_id": service_id,
        "fields": fields,
        "portal_url": portal_url,
        "status": AgentStatus.idle,
        "message": "Session created",
        "user_confirmed_submit": False,
        "screenshot_b64": None,
        "needs_input": None,
        "reference_number": None,
        "browser_page": None,
    }
    return sid


def get(session_id: str) -> Optional[dict]:
    return _SESSIONS.get(session_id)


def update(session_id: str, **kwargs) -> Optional[dict]:
    s = _SESSIONS.get(session_id)
    if not s:
        return None
    s.update(kwargs)
    return s


def set_confirmed(session_id: str, confirmed: bool) -> bool:
    s = _SESSIONS.get(session_id)
    if not s:
        return False
    s["user_confirmed_submit"] = confirmed
    return True


def can_submit(session_id: str) -> bool:
    """HARD-CODED gate — AI cannot bypass this."""
    s = _SESSIONS.get(session_id)
    if not s:
        return False
    return bool(s.get("user_confirmed_submit") is True)


def delete(session_id: str) -> None:
    _SESSIONS.pop(session_id, None)


def wipe_all() -> int:
    n = len(_SESSIONS)
    _SESSIONS.clear()
    return n
