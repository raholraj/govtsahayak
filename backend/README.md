# GovtSahayak Agent Backend (Phase 3)

FastAPI + Playwright. **Submit only after explicit user `HAAN`.**

## Run

```bash
cd backend
chmod +x run.sh
./run.sh
```

API: http://127.0.0.1:8000  |  Docs: http://127.0.0.1:8000/docs

## Safety

- `session_store.can_submit()` must be True
- Only set when user sends HAAN
- CAPTCHA never auto-solved
