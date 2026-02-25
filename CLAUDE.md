# VisionClaw — Guide for AI Assistants

This file provides a concise reference for AI assistants working in this repository. Read this before making changes to understand the project structure, conventions, and workflows.

For full user-facing documentation, see [README.md](README.md).

---

## Project Overview

VisionClaw connects Meta Ray-Ban glasses (or a phone camera) to Google Gemini Live AI for real-time voice and vision interaction. The AI can respond with voice and trigger 56+ agentic actions (messaging, web search, etc.) through an **OpenClaw** HTTP gateway running on a local Mac.

**Two sample apps:**
- `samples/CameraAccess/` — iOS (Swift, SwiftUI, Xcode)
- `samples/CameraAccessAndroid/` — Android (Kotlin, Jetpack Compose, Gradle)

Both apps share the same architecture and parallel module structure.

---

## Repository Structure

```
VisionClaw/
├── samples/
│   ├── CameraAccess/               # iOS sample app
│   │   ├── CameraAccess.xcodeproj
│   │   └── CameraAccess/
│   │       ├── CameraAccessApp.swift       # SwiftUI entry point
│   │       ├── Gemini/                     # Gemini Live WebSocket integration
│   │       ├── OpenClaw/                   # Tool calling & OpenClaw HTTP client
│   │       ├── WebRTC/                     # Glasses streaming via WebRTC
│   │       ├── iPhone/                     # Phone camera (AVCaptureSession)
│   │       ├── Settings/                   # UserDefaults-backed config
│   │       ├── Views/                      # SwiftUI views
│   │       └── ViewModels/                 # ObservableObject view models
│   └── CameraAccessAndroid/        # Android sample app
│       └── app/src/main/java/.../cameraaccess/
│           ├── MainActivity.kt             # Activity entry point
│           ├── gemini/                     # Gemini Live WebSocket integration
│           ├── openclaw/                   # Tool calling & OpenClaw HTTP client
│           ├── phone/                      # Phone camera (CameraX)
│           ├── settings/                   # DataStore-backed config
│           ├── ui/                         # Jetpack Compose UI
│           └── stream/                     # Stream state & ViewModel
├── assets/                         # Documentation images
├── README.md
├── CONTRIBUTING.md
└── CHANGELOG.md
```

---

## Architecture

### Data Flow

```
Device Camera/Mic
  ↓  16kHz PCM audio + 1fps JPEG video frames
Gemini Live WebSocket (WSS to Google API)
  ↓  toolCall: { execute(task: "send a message to Alice") }
ToolCallRouter
  ↓  POST /v1/chat/completions
OpenClaw HTTP Gateway (local Mac, port 18789 default)
  ↓  56+ skills execute on Mac
Response → back through pipeline → Gemini → voice response to user
```

### Key Design Patterns

- **MVVM**: ViewModels hold state and business logic; Views are purely reactive.
  - iOS: `ObservableObject` + `@Published` properties
  - Android: `StateFlow` / `MutableStateFlow` in `ViewModel`
- **Service layer**: Dedicated classes for each concern — `GeminiLiveService` (WebSocket), `AudioManager`, `OpenClawBridge` (HTTP), `SettingsManager`
- **Tool calling**: A single `execute` tool receives a natural-language task string and delegates to OpenClaw
- **Connection state enums**: `GeminiConnectionState` (disconnected → connecting → settingUp → ready → error) used consistently on both platforms

---

## Development Setup

### iOS

Requirements: Xcode 15+, iOS 17+ device, Gemini API key

```bash
cd samples/CameraAccess
cp CameraAccess/Secrets.swift.example CameraAccess/Secrets.swift
# Edit Secrets.swift — set geminiAPIKey; optionally set openClawHost, openClawPort, openClawGatewayToken
open CameraAccess.xcodeproj
# In Xcode: select a physical iPhone target → Cmd+R to build and run
```

### Android

Requirements: Android Studio, Android 14+ device (API 34+), Gemini API key, GitHub PAT

```bash
cd samples/CameraAccessAndroid
# Copy and edit Secrets file
cp app/src/main/java/com/meta/wearable/dat/externalsampleapps/cameraaccess/Secrets.kt.example \
   app/src/main/java/com/meta/wearable/dat/externalsampleapps/cameraaccess/Secrets.kt
# Edit Secrets.kt — set geminiAPIKey; optionally set openClaw fields

# GitHub token is required to download the Meta DAT SDK from GitHub Packages
echo "github_token=<your_PAT_with_packages:read>" >> local.properties

# Open in Android Studio → sync Gradle → run on device
```

`local.properties` and `Secrets.kt` are both gitignored — never commit them.

---

## Building and Testing

### iOS

| Action | Method |
|--------|--------|
| Build | Xcode → Product → Build (Cmd+B) |
| Run | Xcode → Product → Run on device (Cmd+R) |
| Test | Xcode → Product → Test (Cmd+U) |

Tests use **XCTest** with `MockDeviceKit` to simulate Ray-Ban glasses without hardware.
Test file: `samples/CameraAccess/CameraAccessTests/CameraAccessTests.swift`

### Android

| Action | Command |
|--------|---------|
| Build | `./gradlew assembleDebug` |
| Run | Android Studio → Run (Shift+F10) |
| Test | `./gradlew connectedAndroidTest` |

Tests use **AndroidJUnit4** + Compose UI testing with `MockDeviceKit`.
Test file: `app/src/androidTest/java/.../InstrumentationTest.kt`

No CI/CD is configured — all builds and tests run locally.

---

## Key Conventions

### iOS (Swift)

- **Naming**: `camelCase` for variables/functions, `PascalCase` for types
- **Logging**: `NSLog("[ServiceName] message: %@", value)` — bracket-prefixed tag per service
- **Async**: `async/await` with `@MainActor` for all UI state updates
- **State**: `class MyViewModel: ObservableObject { @Published var foo = ... }`
- **Error handling**: guard statements for early returns, optional binding for nil-safety

### Android (Kotlin)

- **Naming**: `camelCase` for variables/functions, `PascalCase` for types, `UPPER_SNAKE_CASE` for constants
- **Logging**: `Log.d(TAG, "message")` with `private const val TAG = "ClassName"` declared per file
- **Async**: `viewModelScope.launch { }` for ViewModel ops, `withContext(Dispatchers.IO)` for background work
- **State**: `private val _foo = MutableStateFlow(...)` exposed as `val foo: StateFlow<...> = _foo.asStateFlow()`
- **Error handling**: sealed class results for typed outcomes, try/catch with `Exception`

### Shared Conventions (Both Platforms)

- Modules are named identically across platforms (e.g., `GeminiLiveService.swift` ↔ `GeminiLiveService.kt`)
- Connection state enums follow the same shape: `disconnected → connecting → settingUp → ready → error`
- **Never commit secrets** — `Secrets.swift` and `Secrets.kt` are gitignored; use the `.example` templates
- Configuration priority (highest to lowest): runtime UI settings → Secrets file → hardcoded defaults in config class

---

## Key Files Reference

| Purpose | iOS | Android |
|---------|-----|---------|
| Gemini API config + system prompt | `Gemini/GeminiConfig.swift` | `gemini/GeminiConfig.kt` |
| WebSocket connection management | `Gemini/GeminiLiveService.swift` | `gemini/GeminiLiveService.kt` |
| Session lifecycle & state | `Gemini/GeminiSessionViewModel.swift` | `gemini/GeminiSessionViewModel.kt` |
| Audio capture/playback | `Gemini/AudioManager.swift` | `gemini/AudioManager.kt` |
| OpenClaw HTTP client | `OpenClaw/OpenClawBridge.swift` | `openclaw/OpenClawBridge.kt` |
| Tool call routing | `OpenClaw/ToolCallRouter.swift` | `openclaw/ToolCallRouter.kt` |
| Tool data models | `OpenClaw/ToolCallModels.swift` | `openclaw/ToolCallModels.kt` |
| Settings management | `Settings/SettingsManager.swift` | `settings/SettingsManager.kt` |
| App entry point | `CameraAccessApp.swift` | `MainActivity.kt` |
| Local secrets (gitignored) | `CameraAccess/Secrets.swift` | `app/.../Secrets.kt` |
| Version catalog (Android deps) | — | `gradle/libs.versions.toml` |

---

## API Integration Details

### Gemini Live WebSocket

- **Endpoint**: `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key={apiKey}`
- **Model**: `models/gemini-2.5-flash-native-audio-preview-12-2025`
- **Audio in**: PCM Int16, 16 kHz, mono (sent as binary WebSocket frames)
- **Audio out**: PCM 24 kHz (received as binary frames)
- **Video**: 1fps JPEG frames sent as base64 in JSON messages

### Tool Calling Protocol

Gemini sends a tool call; the app routes it to OpenClaw and returns the result:

```json
// Incoming from Gemini
{ "toolCall": { "functionCalls": [{ "id": "123", "name": "execute", "args": { "task": "send a text to Alice saying I'll be late" } }] } }

// App response to Gemini
{ "toolResponse": { "functionResponses": [{ "id": "123", "name": "execute", "response": { "output": "Message sent." } }] } }
```

### OpenClaw Gateway

- **Endpoint**: `http://{openClawHost}:{openClawPort}/v1/chat/completions`
- **Default port**: 18789
- **Auth**: `Authorization: Bearer {token}` header + `x-openclaw-session-key: {key}` for conversation continuity
- **Request body**: `{ "model": "openclaw", "messages": [...], "stream": false }`

---

## Contributing

- Pull requests are imported into Meta's internal repository rather than merged directly on GitHub
- A CLA is required for all contributors
- Bug reports and feature requests go to GitHub Issues
- No linting configuration is enforced — match the existing code style for the platform you're editing
- Security issues: see the security bounty program referenced in CONTRIBUTING.md
