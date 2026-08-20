import httpx
from models.schemas import HealthCheckResponse


async def check_portal(url: str, timeout: float = 12.0) -> HealthCheckResponse:
    try:
        async with httpx.AsyncClient(
            follow_redirects=True,
            timeout=timeout,
            headers={"User-Agent": "GovtSahayak/0.3 (assist-only)"},
        ) as client:
            resp = await client.get(url)
            live = 200 <= resp.status_code < 500
            if live:
                return HealthCheckResponse(
                    url=url,
                    live=True,
                    status_code=resp.status_code,
                    message="Portal live hai, apply kar sakte hain.",
                )
            return HealthCheckResponse(
                url=url,
                live=False,
                status_code=resp.status_code,
                message=f"Portal issue (HTTP {resp.status_code}). Guided mode use karo.",
            )
    except httpx.TimeoutException:
        return HealthCheckResponse(url=url, live=False, message="Portal timeout.")
    except Exception as e:
        return HealthCheckResponse(
            url=url, live=False, message=f"Portal check fail: {type(e).__name__}"
        )
