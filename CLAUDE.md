# VisionClaw — Guide for AI Assistants

This file provides a dense, AI-optimized reference for working in this repository. Read this before making changes.

For user-facing documentation, see [README.md](README.md).

---

## Project Overview

VisionClaw is a Meta open-source project connecting Meta Ray-Ban glasses (or a phone camera) to Google Gemini Live AI for real-time voice and vision interaction. The AI responds with voice and triggers 56+ agentic actions (messaging, web search, etc.) through an **OpenClaw** HTTP gateway running on a local Mac.

This is a **sample application** demonstrating the Meta Wearables DAT SDK — not a library.

**Two sample apps:**
- `samples/CameraAccess/` — iOS (Swift, SwiftUI, Xcode)
- `samples/CameraAccessAndroid/` — Android (Kotlin, Jetpack Compose, Gradle)

**Contributing note:** GitHub PRs are imported into Meta's internal repository, not merged directly on GitHub. PRs may remain "open" after changes appear internally — this is expected.

---

## Architecture

### Data Flow

```
Device Camera/Mic (glasses or phone)
  |
  | DAT SDK video frames (~1fps JPEG throttled) + PCM audio (16kHz)
  v
App (iOS: AVCaptureSession / Android: CameraX)
  |
  | WebSocket (WSS, text + binary frames)
  v
Gemini Live API  wss://generativelanguage.googleapis.com/ws/...
  |
  |-- Audio response (PCM 24kHz) --> AudioManager --> Speaker
  |-- toolCall message --> ToolCallRouter
  |                              |
  |                              | HTTP POST /v1/chat/completions
  |                              v
  |                        OpenClaw Gateway (local Mac, port 18789)
  |                              |
  |                              v
  |                        56+ skills execute on Mac
  |                              |
  |<-- toolResponse <------------+
  v
Gemini speaks the result to user
```

### Protocol Details

- **Connection states**: `disconnected → connecting → settingUp → ready → error`. The `setupComplete` server message triggers `ready`.
- **Audio IN**: PCM Int16, 16kHz, mono, ~100ms chunks, base64 in `realtimeInput.audio`
- **Audio OUT**: PCM Int16, 24kHz, mono, base64 in `serverContent.modelTurn.parts[].inlineData`
- **Video**: JPEG at 50% quality, throttled to ~1fps, base64 in `realtimeInput.video`
- **Tool call shape (incoming)**:
  ```json
  { "toolCall": { "functionCalls": [{ "id": "123", "name": "execute", "args": { "task": "send a text to Alice" } }] } }
  ```
- **Tool response shape (outgoing)**:
  ```json
  { "toolResponse": { "functionResponses": [{ "id": "123", "name": "execute", "response": { "output": "Message sent." } }] } }
  ```
- **Only one tool is declared**: `execute(task: string)` — routes everything through OpenClaw
- **`goAway`** message: server is about to close the connection
- **`toolCallCancellation`** message: cancel in-flight tool calls (user interrupted)

### Key Design Patterns

- **MVVM**: ViewModels hold state and business logic; Views are purely reactive.
  - iOS: `ObservableObject` + `@Published` properties
  - Android: `StateFlow` / `MutableStateFlow` in `ViewModel`
- **Service layer**: Dedicated classes per concern — `GeminiLiveService` (WebSocket), `AudioManager`, `OpenClawBridge` (HTTP), `SettingsManager`
- **Config priority** (highest → lowest): runtime UI settings → Secrets file → hardcoded defaults in config class

---

## Repository Structure

```
VisionClaw/
  README.md               — User-facing docs and setup guide
  CHANGELOG.md            — SDK version history
  CONTRIBUTING.md         — Meta OSS contribution process
  samples/
    CameraAccess/          — iOS sample app (Swift, Xcode project)
      CameraAccess.xcodeproj
      CameraAccess/
        CameraAccessApp.swift           — App entry point, SDK init
        Gemini/
          GeminiConfig.swift            — Model name, audio/video params, system prompt
          GeminiLiveService.swift       — WebSocket client for Gemini Live
          AudioManager.swift            — AVAudioEngine mic capture + playback
          GeminiSessionViewModel.swift  — Session lifecycle, wires all components
        OpenClaw/
          ToolCallModels.swift          — GeminiToolCall, ToolResult, ToolDeclarations
          OpenClawBridge.swift          — HTTP POST to OpenClaw gateway
          ToolCallRouter.swift          — Routes tool calls, manages cancellation
        iPhone/
          IPhoneCameraManager.swift     — AVCaptureSession for phone camera mode
        WebRTC/
          WebRTCClient.swift            — WebRTC peer connection (glasses POV streaming)
          SignalingClient.swift         — WebSocket signaling for WebRTC rooms
          WebRTCSessionViewModel.swift
          WebRTCConfig.swift
          CustomVideoCapturer.swift
        Settings/
          SettingsManager.swift         — UserDefaults wrapper (falls back to Secrets)
          SettingsView.swift
        Views/                          — SwiftUI views
        ViewModels/                     — StreamSessionViewModel, WearablesViewModel
        Secrets.swift.example           — Template for secrets (copy to Secrets.swift)
      CameraAccessTests/
        CameraAccessTests.swift         — XCTest integration tests using MockDeviceKit
      server/                           — Node.js WebRTC signaling server
        index.js
        package.json

    CameraAccessAndroid/   — Android sample app (Kotlin, Gradle)
      app/
        build.gradle.kts
        src/main/java/com/meta/wearable/dat/externalsampleapps/cameraaccess/
          MainActivity.kt              — Entry point, permission requests, SDK init
          Secrets.kt.example           — Template for secrets (copy to Secrets.kt)
          gemini/
            GeminiConfig.kt            — Model name, audio/video params (mirrors iOS)
            GeminiLiveService.kt       — OkHttp WebSocket client
            AudioManager.kt            — AudioRecord + AudioTrack
            GeminiSessionViewModel.kt  — Session lifecycle
          openclaw/
            ToolCallModels.kt          — Data classes mirroring iOS models
            OpenClawBridge.kt          — OkHttp HTTP client
            ToolCallRouter.kt          — Routes tool calls, coroutine-based
          phone/
            PhoneCameraManager.kt      — CameraX phone camera mode
          webrtc/
            WebRTCClient.kt
            SignalingClient.kt
            WebRTCSessionViewModel.kt
            WebRTCConfig.kt
            CustomVideoCapturer.kt
          settings/
            SettingsManager.kt         — SharedPreferences (falls back to Secrets)
          ui/                          — Jetpack Compose screens and components
          wearables/
            WearablesViewModel.kt
            WearablesUiState.kt
        src/androidTest/.../InstrumentationTest.kt  — Compose UI tests
      settings.gradle.kts              — GitHub Packages repo for Meta DAT SDK
      local.properties                 — github_token goes here (gitignored)
      gradle/libs.versions.toml        — Dependency version catalog
```

---

## Development Setup

### iOS

Requirements: Xcode 15+, iOS 17+ physical device, Gemini API key

```bash
# 1. Create secrets file
cp samples/CameraAccess/CameraAccess/Secrets.swift.example \
   samples/CameraAccess/CameraAccess/Secrets.swift
# Edit: set geminiAPIKey (required); optionally openClawHost, openClawPort, openClawGatewayToken

# 2. Open project
open samples/CameraAccess/CameraAccess.xcodeproj
# In Xcode: select a physical iPhone target → Cmd+R to build and run

# 3. (Optional) WebRTC signaling server for glasses streaming
cd samples/CameraAccess/server && npm install && npm start
# Then set webrtcSignalingURL in Secrets.swift to ws://YOUR_MAC_IP:8080
```

**Note:** Simulator does NOT support camera or Bluetooth — physical device required for glasses path. Phone camera mode works in simulator for UI development only.

### Android

Requirements: Android Studio, Android 14+ device (API 34+), Gemini API key, GitHub PAT

```bash
# 1. Add GitHub token to local.properties (gitignored)
echo "github_token=YOUR_PAT" >> samples/CameraAccessAndroid/local.properties
# Token needs read:packages scope — required even for public GitHub Packages
# Get token: gh auth token  or  github.com/settings/tokens

# 2. Create secrets file
cp samples/CameraAccessAndroid/app/src/main/java/com/meta/wearable/dat/externalsampleapps/cameraaccess/Secrets.kt.example \
   samples/CameraAccessAndroid/app/src/main/java/com/meta/wearable/dat/externalsampleapps/cameraaccess/Secrets.kt
# Edit: set geminiAPIKey (required)

# 3. Open samples/CameraAccessAndroid/ in Android Studio → Sync Gradle → Run (Shift+F10)
```

**`local.properties` and `Secrets.kt` are gitignored — never commit them.**

### OpenClaw Gateway (Optional)

```bash
# On Mac: configure ~/.openclaw/openclaw.json with gateway.bind="lan"
openclaw gateway restart
curl http://localhost:18789/health

# In app Secrets: set openClawHost="http://YOUR_MAC_HOSTNAME.local", port=18789, token
# Find hostname: scutil --get LocalHostName  (Mac)
```

---

## Key Commands

```bash
# iOS: open project
open samples/CameraAccess/CameraAccess.xcodeproj

# iOS: run tests
xcodebuild test -project samples/CameraAccess/CameraAccess.xcodeproj \
  -scheme CameraAccess -destination 'platform=iOS Simulator,name=iPhone 16'

# Android: build debug APK
cd samples/CameraAccessAndroid && ./gradlew assembleDebug

# Android: run instrumented tests (requires connected device)
cd samples/CameraAccessAndroid && ./gradlew connectedAndroidTest

# Android: install on connected device
cd samples/CameraAccessAndroid && ./gradlew installDebug

# WebRTC signaling server
cd samples/CameraAccess/server && npm install && npm start
```

No linting tools configured (no SwiftLint, Ktlint, or ESLint config files). No pre-commit hooks. No CI/CD.

---

## Coding Conventions

### iOS (Swift)

- **Naming**: `camelCase` for variables/functions, `PascalCase` for types — no prefixes
- **Threading**: `@MainActor` on all ViewModels and UI-touching classes; `Task { @MainActor in ... }` for async UI updates from callbacks
- **Logging**: `NSLog("[ServiceName] message: %@", value)`. Tags in use: `[Gemini]`, `[OpenClaw]`, `[ToolCall]`, `[Audio]`, `[iPhoneCamera]`, `[Latency]`
- **Async**: Swift Concurrency (`async/await`, `Task`, `CheckedContinuation`) — no Combine
- **State**: `class MyViewModel: ObservableObject { @Published var foo = ... }`; `@StateObject` at injection point, `@ObservedObject` for passed instances
- **Error handling**: `do/catch`, descriptive `errorMessage` strings surfaced to UI; avoid force-unwrap (`!`); use guard-let or optional chaining

### Android (Kotlin)

- **Naming**: `camelCase` for variables/functions, `PascalCase` for types, `UPPER_SNAKE_CASE` for constants (`TAG`, `MAX_HISTORY_TURNS`, etc.)
- **Logging**: `Log.d(TAG, "message")` with `private const val TAG = "ClassName"` in companion object; `Log.e` for errors
- **Async**: `viewModelScope.launch { }` for ViewModel coroutines, `withContext(Dispatchers.IO)` for network/disk
- **State**: `private val _foo = MutableStateFlow(...)` exposed as `val foo: StateFlow<...> = _foo.asStateFlow()` — never expose `MutableStateFlow` publicly
- **Error handling**: sealed classes for typed results, `try/catch` with `Exception`
- **Package**: `com.meta.wearable.dat.externalsampleapps.cameraaccess`

### Shared

- Modules named identically across platforms (e.g., `GeminiLiveService.swift` ↔ `GeminiLiveService.kt`)
- Connection state enums follow the same shape on both platforms
- **Never commit secrets** — `Secrets.swift` and `Secrets.kt` are gitignored; use `.example` templates

---

## iOS/Android Symmetry

Every major class has a direct counterpart. When adding a feature, implement it on both platforms following the same structure. The iOS version is generally the reference implementation.

| Concern | iOS | Android |
|---|---|---|
| Gemini WebSocket | `GeminiLiveService.swift` (URLSession) | `GeminiLiveService.kt` (OkHttp) |
| Audio | `AudioManager.swift` (AVAudioEngine) | `AudioManager.kt` (AudioRecord/AudioTrack) |
| Config | `GeminiConfig.swift` (enum with static vars) | `GeminiConfig.kt` (object) |
| Session VM | `GeminiSessionViewModel.swift` (@MainActor class) | `GeminiSessionViewModel.kt` (ViewModel + viewModelScope) |
| Tool call router | `ToolCallRouter.swift` (Task-based) | `ToolCallRouter.kt` (coroutine Job-based) |
| OpenClaw bridge | `OpenClawBridge.swift` (URLSession) | `OpenClawBridge.kt` (OkHttp + suspend) |
| Phone camera | `IPhoneCameraManager.swift` (AVCaptureSession) | `PhoneCameraManager.kt` (CameraX) |
| WebRTC | `WebRTCClient.swift` | `WebRTCClient.kt` |
| Settings | `SettingsManager.swift` (UserDefaults) | `SettingsManager.kt` (SharedPreferences) |
| Secrets | `Secrets.swift` (enum, gitignored) | `Secrets.kt` (object, gitignored) |
| Entry point | `CameraAccessApp.swift` | `MainActivity.kt` |

---

## Important Gotchas

**Secrets files must be created manually.** `Secrets.swift` and `Secrets.kt` are never in the repository. New clones will fail to build until the developer copies the `.example` file. Never assume these files exist.

**Physical device required.** The DAT SDK communicates with Meta Ray-Ban glasses via Bluetooth. The iOS simulator cannot run the glasses streaming path.

**Gemini binary frames contain JSON, not binary audio.** The Gemini Live WebSocket sends both text and binary frames. Binary frames contain UTF-8-encoded JSON — not raw audio data. Both frame types must be decoded as strings. This is a common bug source.

**Audio session mode matters on iOS.** iPhone mode uses `.voiceChat` for aggressive AEC (co-located mic + speaker). Glasses mode uses `.videoChat` (mic on glasses, speaker on phone). Switching modes requires reconfiguring `AVAudioSession`. The mic is also muted during AI speech in iPhone mode to prevent echo.

**SettingsManager must be initialized on Android.** `SettingsManager.init(context)` must be called in `MainActivity.onCreate` before any code accesses `GeminiConfig`. Calling config getters before `init` will crash (lateinit var not initialized).

**OpenClaw session continuity.** `OpenClawBridge` maintains a `conversationHistory` array and a `sessionKey` header (`x-openclaw-session-key: agent:main:glass:<timestamp>`). Each Gemini session gets a fresh conversation — call `resetSession()` on start. History is trimmed to the last 10 turns (20 messages). Do not bypass this history mechanism.

**Tool call cancellation must NOT send a toolResponse.** When `toolCallCancellation` is received, `ToolCallRouter` cancels the in-flight `Task`/`Job` and must NOT send a `toolResponse` for the cancelled call.

**Video throttling must be kept.** Both apps throttle camera frames to ~1fps before sending to Gemini. `GeminiSessionViewModel.sendVideoFrameIfThrottled` checks elapsed time. Do not remove this — Gemini's WebSocket has bandwidth limits.

**GitHub Packages auth for DAT SDK.** The Android Meta DAT SDK is distributed via `https://maven.pkg.github.com/facebook/meta-wearables-dat-android`. A GitHub PAT with `read:packages` scope is required even though the package is public. The property name in `local.properties` must be exactly `github_token` (not `gpr.token`) — `settings.gradle.kts` calls `localProperties.getProperty("github_token")`.

**No network mocking in tests.** The existing tests use `MockDeviceKit` to simulate glasses but do NOT mock Gemini or OpenClaw. Tests requiring network access will fail without real credentials.

---

## Key Files Quick Reference

**iOS** (paths relative to `samples/CameraAccess/CameraAccess/`):

| File | Edit when... |
|---|---|
| `Gemini/GeminiConfig.swift` | Changing model, audio params, video FPS, system prompt, API key source |
| `Gemini/GeminiLiveService.swift` | Modifying WebSocket protocol, message handling, connection state machine |
| `Gemini/AudioManager.swift` | Changing audio format, sample rate, echo cancellation, playback behavior |
| `Gemini/GeminiSessionViewModel.swift` | Changing session lifecycle, wiring new event handlers, transcript logic |
| `OpenClaw/ToolCallModels.swift` | Adding new tools, changing tool declaration, modifying ToolResult structure |
| `OpenClaw/OpenClawBridge.swift` | Changing HTTP request format, session key logic, conversation history |
| `OpenClaw/ToolCallRouter.swift` | Changing routing logic, cancellation behavior |
| `iPhone/IPhoneCameraManager.swift` | Changing phone camera resolution, orientation, capture settings |
| `Settings/SettingsManager.swift` | Adding new user-configurable settings |
| `Secrets.swift.example` | Adding new secret fields (update example, never the real file) |

**Android** (paths relative to `samples/CameraAccessAndroid/app/src/main/java/.../cameraaccess/`):

| File | Edit when... |
|---|---|
| `gemini/GeminiConfig.kt` | Same as iOS counterpart |
| `gemini/GeminiLiveService.kt` | Same as iOS counterpart |
| `gemini/AudioManager.kt` | Same as iOS counterpart |
| `gemini/GeminiSessionViewModel.kt` | Same as iOS counterpart |
| `openclaw/ToolCallModels.kt` | Same as iOS counterpart |
| `openclaw/OpenClawBridge.kt` | Same as iOS counterpart |
| `openclaw/ToolCallRouter.kt` | Same as iOS counterpart |
| `phone/PhoneCameraManager.kt` | Same as iOS IPhoneCameraManager |
| `settings/SettingsManager.kt` | Adding new user-configurable settings |
| `Secrets.kt.example` | Adding new secret fields |
| `../../../../../../settings.gradle.kts` | Changing DAT SDK source or credentials mechanism |

---

## Testing

**iOS:**
- File: `samples/CameraAccess/CameraAccessTests/CameraAccessTests.swift`
- Framework: XCTest + `MWDATMockDevice`
- Tests use `MockDeviceKit.shared.pairRaybanMeta()` to simulate glasses; video set via `mockCameraKit.setCameraFeed(fileURL:)`
- Run: Xcode Test Navigator or `xcodebuild test`

**Android:**
- File: `samples/CameraAccessAndroid/app/src/androidTest/.../InstrumentationTest.kt`
- Framework: Compose UI testing (JUnit4 + `createAndroidComposeRule`)
- Tests use `MockDeviceKit.getInstance(context).pairRaybanMeta()`
- Run: Android Studio or `./gradlew connectedAndroidTest` (requires connected device)

Neither platform has unit tests for Gemini or OpenClaw. If adding unit tests, mock the URLSession/OkHttp layer — do not make live network calls.

---

## External Dependencies

**iOS** (Swift Package Manager, managed in Xcode project):
- `MWDATCore` — Meta Wearables DAT SDK (glasses streaming, registration)
- `MWDATMockDevice` — Mock device for testing (DEBUG only)
- `MWDATCamera` — Camera streaming from glasses
- WebRTC framework (vendor-included)

**Android** (Gradle, see `gradle/libs.versions.toml`):
- `mwdat.core`, `mwdat.camera`, `mwdat.mockdevice` — Meta DAT SDK from GitHub Packages
- `okhttp` — HTTP and WebSocket client (Gemini + OpenClaw)
- `webrtc` (stream-webrtc-android) — WebRTC peer connections
- `camerax.*` — CameraX for phone camera mode
- `androidx.compose.*`, `material3` — UI
- `lifecycle.viewmodel.compose` — ViewModel integration
- `datastore.preferences` — listed in catalog but `SettingsManager` uses `SharedPreferences`; may be unused
- `gson` — listed in catalog; most JSON parsing uses `org.json.JSONObject` directly; may be partially used

---

## API Integration Details

### Gemini Live WebSocket

- **Endpoint**: `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key={apiKey}`
- **Model**: `models/gemini-2.5-flash-native-audio-preview-12-2025`
- **Audio in**: PCM Int16, 16 kHz, mono (sent as base64 in JSON)
- **Audio out**: PCM 24 kHz (received as base64 in JSON)
- **Video**: 1fps JPEG frames sent as base64 in JSON messages

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
