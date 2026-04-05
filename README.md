# GossipHome Automation

Flutter frontend for the CS7NS2 IoT gossip mesh smart-home system.

---

## Running the Flutter app

```bash
# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run

# Run on a specific device (list devices first)
flutter devices
flutter run -d <device-id>

# Build a release APK (Android)
flutter build apk

# Build for iOS
flutter build ios
```

---

## Running the AI server (Gemini)

The AI chat feature requires the Python FastAPI server running locally.

```bash
cd ai

# First-time setup
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Copy and fill in your Gemini API key
cp .env.example .env
# Edit .env and set GEMINI_API_KEY=your_key_here

# Start the server
uvicorn main:app --reload

# Server runs at http://localhost:8000
# Health check: http://localhost:8000/health
```

Once running, set the AI server URL in the app under **Settings → AI Server (Gemini)**.

---

## Cloud backend

The app talks to an AWS Lambda REST API. The base URL is pre-configured in `lib/core/services/api_service.dart`. It can also be changed at runtime under **Settings → Backend → API Base URL**.

Key endpoints:
- `GET /status` — live sensor readings from all rooms
- `POST /command` — queue a command for the ESP32 mesh
- `GET /history` — sensor history per room
- `GET /thresholds` / `PUT /thresholds` — alert thresholds
