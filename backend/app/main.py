import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routers import health, agent, session

app = FastAPI(
    title="GovtSahayak Agent API",
    description="Assist-only backend. Final submit requires explicit user confirmation.",
    version="0.3.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router, prefix="/api", tags=["health"])
app.include_router(session.router, prefix="/api/session", tags=["session"])
app.include_router(agent.router, prefix="/api/agent", tags=["agent"])


@app.get("/")
def root():
    return {
        "app": "GovtSahayak Agent",
        "phase": 3,
        "disclaimer": "Ye API sirf assist karta hai. Final submit user ki responsibility hai.",
    }
