from pydantic import BaseModel, Field
from typing import Optional, Any
from enum import Enum


class AgentStatus(str, Enum):
    idle = "idle"
    checking_portal = "checking_portal"
    filling = "filling"
    waiting_otp = "waiting_otp"
    waiting_captcha = "waiting_captcha"
    waiting_confirm = "waiting_confirm"
    submitted = "submitted"
    error = "error"
    guided_fallback = "guided_fallback"


class StartSessionRequest(BaseModel):
    service_id: str
    fields: dict[str, Any] = Field(default_factory=dict)
    portal_url: Optional[str] = None


class SessionResponse(BaseModel):
    session_id: str
    status: AgentStatus
    message: str
    screenshot_b64: Optional[str] = None
    needs_input: Optional[str] = None
    preview_fields: Optional[dict[str, Any]] = None
    reference_number: Optional[str] = None


class UserInputRequest(BaseModel):
    session_id: str
    input_type: str
    value: str


class HealthCheckRequest(BaseModel):
    url: str


class HealthCheckResponse(BaseModel):
    url: str
    live: bool
    status_code: Optional[int] = None
    message: str
