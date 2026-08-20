from fastapi import APIRouter
from models.schemas import HealthCheckRequest, HealthCheckResponse
from services.portal_health import check_portal

router = APIRouter()


@router.get("/health")
async def api_health():
    return {"status": "ok", "service": "govtsahayak-agent"}


@router.post("/portal-check", response_model=HealthCheckResponse)
async def portal_check(body: HealthCheckRequest):
    return await check_portal(body.url)
