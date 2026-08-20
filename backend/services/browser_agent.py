"""
Playwright browser agent — fills forms, pauses for OTP/CAPTCHA,
NEVER submits without can_submit() == True.
"""
from __future__ import annotations
import asyncio
import base64
import logging
from typing import Optional

from playwright.async_api import async_playwright, Page, Browser

from services import session_store
from models.schemas import AgentStatus

logger = logging.getLogger("browser_agent")

FIELD_SELECTORS = {
    "name": [
        'input[name*="name" i]',
        'input[id*="name" i]',
        'input[placeholder*="name" i]',
        'input[name*="applicant" i]',
    ],
    "dob": [
        'input[name*="dob" i]',
        'input[name*="birth" i]',
        'input[type="date"]',
        'input[id*="dob" i]',
    ],
    "aadhaar_number": [
        'input[name*="aadhaar" i]',
        'input[name*="aadhar" i]',
        'input[id*="aadhaar" i]',
        'input[placeholder*="aadhaar" i]',
    ],
    "address": [
        'textarea[name*="address" i]',
        'input[name*="address" i]',
        'textarea[id*="address" i]',
    ],
    "mobile": [
        'input[name*="mobile" i]',
        'input[name*="phone" i]',
        'input[type="tel"]',
    ],
    "email": [
        'input[name*="email" i]',
        'input[type="email"]',
    ],
    "income": [
        'input[name*="income" i]',
        'input[id*="income" i]',
    ],
}


class BrowserAgent:
    def __init__(self):
        self._playwright = None
        self._browser: Optional[Browser] = None

    async def ensure_browser(self):
        if self._browser is None:
            self._playwright = await async_playwright().start()
            self._browser = await self._playwright.chromium.launch(
                headless=True,
                args=["--no-sandbox", "--disable-dev-shm-usage"],
            )
        return self._browser

    async def close(self):
        if self._browser:
            await self._browser.close()
            self._browser = None
        if self._playwright:
            await self._playwright.stop()
            self._playwright = None

    async def _screenshot_b64(self, page: Page) -> str:
        data = await page.screenshot(type="png", full_page=False)
        return base64.b64encode(data).decode("ascii")

    async def _try_fill(self, page: Page, field_key: str, value: str) -> bool:
        selectors = FIELD_SELECTORS.get(field_key, [
            f'input[name*="{field_key}" i]',
            f'input[id*="{field_key}" i]',
        ])
        for sel in selectors:
            try:
                loc = page.locator(sel).first
                if await loc.count() > 0 and await loc.is_visible(timeout=1500):
                    await loc.fill(str(value))
                    logger.info("Filled %s via %s", field_key, sel)
                    return True
            except Exception:
                continue
        return False

    async def start_fill(self, session_id: str) -> dict:
        s = session_store.get(session_id)
        if not s:
            return {"status": AgentStatus.error, "message": "Session not found"}

        url = s["portal_url"]
        fields = s.get("fields") or {}

        session_store.update(
            session_id,
            status=AgentStatus.filling,
            message="Portal open karke form bhar raha hoon...",
        )

        try:
            browser = await self.ensure_browser()
            context = await browser.new_context(
                viewport={"width": 1280, "height": 720},
                user_agent=(
                    "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
                ),
            )
            page = await context.new_page()
            s["browser_page"] = page
            s["browser_context"] = context

            await page.goto(url, wait_until="domcontentloaded", timeout=45000)
            await asyncio.sleep(1.5)

            filled = []
            for key, val in fields.items():
                if val is None or str(val).strip() in ("", "UNCLEAR"):
                    continue
                ok = await self._try_fill(page, key, str(val))
                if ok:
                    filled.append(key)

            shot = await self._screenshot_b64(page)
            content = (await page.content()).lower()

            if "otp" in content or "one time" in content:
                needs, status = "otp", AgentStatus.waiting_otp
                msg = "OTP field dikha — mobile pe OTP aaya hoga. Type karke bhejo."
            elif "captcha" in content:
                needs, status = "captcha", AgentStatus.waiting_captcha
                msg = "CAPTCHA aaya hai — solve karke text bhejo. Main wait karta hoon."
            else:
                needs, status = "confirm", AgentStatus.waiting_confirm
                msg = (
                    f"Form partially filled ({len(filled)} fields). "
                    "Screenshot dekho. Submit se pehle HAAN likho."
                )

            session_store.update(
                session_id,
                status=status,
                message=msg,
                screenshot_b64=shot,
                needs_input=needs,
                preview_fields={k: fields[k] for k in filled if k in fields},
            )
            return session_store.get(session_id)

        except Exception as e:
            logger.exception("start_fill failed")
            session_store.update(
                session_id,
                status=AgentStatus.guided_fallback,
                message=f"Automation fail ({type(e).__name__}). Guided mode use karo.",
                needs_input=None,
            )
            return session_store.get(session_id)

    async def provide_input(self, session_id: str, input_type: str, value: str) -> dict:
        s = session_store.get(session_id)
        if not s:
            return {"status": AgentStatus.error, "message": "Session not found"}

        page: Optional[Page] = s.get("browser_page")
        if page is None:
            session_store.update(
                session_id,
                status=AgentStatus.guided_fallback,
                message="Browser session khatam. Guided mode se continue karo.",
            )
            return session_store.get(session_id)

        try:
            if input_type == "otp":
                for sel in [
                    'input[name*="otp" i]',
                    'input[id*="otp" i]',
                    'input[placeholder*="otp" i]',
                    'input[maxlength="6"]',
                ]:
                    try:
                        loc = page.locator(sel).first
                        if await loc.count() > 0:
                            await loc.fill(value)
                            break
                    except Exception:
                        continue
                shot = await self._screenshot_b64(page)
                session_store.update(
                    session_id,
                    status=AgentStatus.waiting_confirm,
                    message="OTP daal diya. Submit ke liye HAAN bhejo.",
                    screenshot_b64=shot,
                    needs_input="confirm",
                )

            elif input_type == "captcha":
                for sel in [
                    'input[name*="captcha" i]',
                    'input[id*="captcha" i]',
                    'input[placeholder*="captcha" i]',
                ]:
                    try:
                        loc = page.locator(sel).first
                        if await loc.count() > 0:
                            await loc.fill(value)
                            break
                    except Exception:
                        continue
                shot = await self._screenshot_b64(page)
                session_store.update(
                    session_id,
                    status=AgentStatus.waiting_confirm,
                    message="CAPTCHA daal diya. Submit ke liye HAAN bhejo.",
                    screenshot_b64=shot,
                    needs_input="confirm",
                )

            elif input_type == "confirm":
                if value.strip().upper() not in ("HAAN", "YES", "CONFIRM", "HAAN JI"):
                    session_store.update(
                        session_id,
                        status=AgentStatus.waiting_confirm,
                        message='Submit nahi hua. Explicit "HAAN" bhejo.',
                        needs_input="confirm",
                    )
                    return session_store.get(session_id)

                session_store.set_confirmed(session_id, True)
                if not session_store.can_submit(session_id):
                    session_store.update(
                        session_id,
                        status=AgentStatus.error,
                        message="Safety gate blocked submit.",
                    )
                    return session_store.get(session_id)

                submitted = False
                for sel in [
                    'button[type="submit"]',
                    'input[type="submit"]',
                    'button:has-text("Submit")',
                    'button:has-text("submit")',
                    'button:has-text("Apply")',
                ]:
                    try:
                        loc = page.locator(sel).first
                        if await loc.count() > 0 and await loc.is_visible(timeout=1000):
                            await loc.click()
                            submitted = True
                            break
                    except Exception:
                        continue

                await asyncio.sleep(2)
                shot = await self._screenshot_b64(page)
                body_text = ""
                try:
                    body_text = await page.inner_text("body")
                except Exception:
                    pass

                ref = None
                for token in body_text.replace("\n", " ").split():
                    if any(x in token.upper() for x in ("PMAY", "REF", "ACK", "APP")) and len(token) > 6:
                        ref = token[:40]
                        break

                if submitted:
                    session_store.update(
                        session_id,
                        status=AgentStatus.submitted,
                        message="Submit attempt complete. Screenshot check karo.",
                        screenshot_b64=shot,
                        needs_input=None,
                        reference_number=ref,
                    )
                else:
                    session_store.update(
                        session_id,
                        status=AgentStatus.guided_fallback,
                        message="Submit button nahi mila. Guided mode se manually submit karo.",
                        screenshot_b64=shot,
                        needs_input=None,
                    )
            else:
                session_store.update(session_id, message=f"Unknown input_type: {input_type}")

            return session_store.get(session_id)

        except Exception as e:
            logger.exception("provide_input failed")
            session_store.update(
                session_id,
                status=AgentStatus.error,
                message=f"Error: {type(e).__name__}: {e}",
            )
            return session_store.get(session_id)


agent = BrowserAgent()
