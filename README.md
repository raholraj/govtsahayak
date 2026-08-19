# 🇮🇳 GovtSahayak

**Har Bharatiya ke jeb mein ek digital cyber-cafe wala.**

AI chatbot jo Hinglish mein baat karke sarkari portals (PM Awas Yojana, Aadhaar, PAN, DigiLocker, NSP Scholarship) pe guide karta hai — documents padhta hai, step-by-step batata hai. **Data sirf phone pe rehta hai.**

> Cyber cafe ke 50 rupaye aur 2 ghante ki jagah — 5 minute mein, free mein, apne phone se.

---

## Features (Phase 1 — Guided Mode)

- WhatsApp-style chat UI
- Hinglish conversation (Gemini 1.5 Flash + Groq/Mistral fallback)
- Speech-to-text (Hindi)
- Camera / Gallery se document photo → Gemini Vision se data extract
- Confidence < 0.8 pe user se confirm
- Local encrypted SQLite (SQLCipher) — **no server**
- Knowledge base of 5 major portals
- Mandatory disclaimer: final submit user ki responsibility

**Phase 2/3 (future):** Semi-auto form fill guidance + Playwright full agent (optional backend).

---

## Setup

### 1. Clone & deps

```bash
git clone https://github.com/raholraj/govtsahayak.git
cd govtsahayak
flutter pub get
```

### 2. API Keys (required for AI)

Create GitHub Secrets (or pass via `--dart-define`):

| Secret | Purpose |
|--------|---------|
| `GEMINI_API_KEY` | Primary (chat + vision) |
| `GROQ_API_KEY` | Fallback |
| `MISTRAL_API_KEY` | 2nd fallback |

Local run:

```bash
flutter run --dart-define=GEMINI_API_KEY=your_key \
            --dart-define=GROQ_API_KEY=your_key
```

### 3. Build APK via GitHub Actions

1. Push to `main`
2. Go to **Actions** → **Build APK** → Run workflow
3. Download artifact `govtsahayak-apk`

Or locally:

```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

---

## Safety rules (hard-coded)

1. No auto-submit without explicit user confirmation (code-level gate in later phases)
2. No Aadhaar/bank data sent to any custom server — only to Gemini/Groq/Mistral APIs for extraction
3. "Delete after use" / wipe option clears SQLite
4. CAPTCHA is never auto-solved (user does it)
5. Clear disclaimer in UI

---

## Project structure

```
lib/
  main.dart
  models/          # ChatMessage, ServiceInfo
  services/        # AI, Storage (encrypted SQLite), Knowledge
  screens/         # ChatScreen
  widgets/         # MessageBubble, TypingIndicator
assets/
  knowledge_base.json
.github/workflows/
  build-apk.yml
```

---

## Privacy

- Data stays on device (encrypted DB)
- Network calls only to AI providers you configure
- App never submits forms on your behalf without your "HAAN"

---

**Tagline:** Cyber cafe ka jhanjhat khatam. Sarkari kaam, ab dost jaisa aasan.
