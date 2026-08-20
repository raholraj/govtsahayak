from fastapi import APIRouter, HTTPException
from models.schemas import UserInputRequest, SessionResponse, AgentStatus
from services import session_store
from services.browser_agent import agent

router = APIRouter()


def _to_response(s: dict) -> SessionResponse:
    return SessionResponse(
        session_id=s["session_id"],
        status=s["status"] if isinstance(s["status"], AgentStatus) else AgentStatus(s["status"]),
        message=s.get("message", ""),
        screenshot_b64=s.get("screenshot_b64"),
        needs_input=s.get("needs_input"),
        preview_fields=s.get("preview_fields"),
        reference_number=s.get("reference_number"),
    )


@router.post("/fill/{session_id}", response_model=SessionResponse)
async def start_fill(session_id: str):
    s = session_store.get(session_id)
    if not s:
        raise HTTPException(404, "Session not found")
    result = await agent.start_fill(session_id)
    return _to_response(result)


@router.post("/input", response_model=SessionResponse)
async def user_input(body: UserInputRequest):
    s = session_store.get(body.session_id)
    if not s:
        raise HTTPException(404, "Session not found")
    if body.input_type == "confirm":
        if body.value.strip().upper() not in ("HAAN", "YES", "CONFIRM", "HAAN JI"):
            session_store.update(
                body.session_id,
                status=AgentStatus.waiting_confirm,
                message='Submit blocked. Explicit "HAAN" required.',
                needs_input="confirm",
            )
            return _to_response(session_store.get(body.session_id))
    result = await agent.provide_input(body.session_id, body.input_type, body.value)
    return _to_response(result)
