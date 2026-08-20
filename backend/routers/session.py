from fastapi import APIRouter, HTTPException
from models.schemas import StartSessionRequest, SessionResponse, AgentStatus
from services import session_store

router = APIRouter()

PORTALS = {
    "pm_awas_yojana": "https://pmaymis.gov.in",
    "aadhaar_update": "https://myaadhaar.uidai.gov.in",
    "pan_card": "https://www.onlineservices.nsdl.com",
    "digilocker": "https://www.digilocker.gov.in",
    "scholarship_nsp": "https://scholarships.gov.in",
}


@router.post("/start", response_model=SessionResponse)
async def start_session(body: StartSessionRequest):
    url = body.portal_url or PORTALS.get(body.service_id)
    if not url:
        raise HTTPException(400, "Unknown service_id and no portal_url")
    sid = session_store.create_session(body.service_id, body.fields, url)
    return SessionResponse(
        session_id=sid,
        status=AgentStatus.idle,
        message="Session ready. Call /api/agent/fill/{session_id}",
        preview_fields=body.fields,
    )


@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(session_id: str):
    s = session_store.get(session_id)
    if not s:
        raise HTTPException(404, "Session not found")
    return SessionResponse(
        session_id=s["session_id"],
        status=s["status"],
        message=s.get("message", ""),
        screenshot_b64=s.get("screenshot_b64"),
        needs_input=s.get("needs_input"),
        preview_fields=s.get("preview_fields"),
        reference_number=s.get("reference_number"),
    )


@router.delete("/{session_id}")
async def end_session(session_id: str):
    session_store.delete(session_id)
    return {"ok": True}
