# CameraAccess iOS — Contexte détaillé

> Lire aussi : `/home/user/VisionClaw/CLAUDE.md` pour le contexte global.

## Stack technique

- **Swift 5.9+**, **SwiftUI**, **Xcode 15+**
- Pattern **MVVM** : Views observent des ViewModels via `@ObservedObject` / `@StateObject`
- `@MainActor` obligatoire sur tous les ViewModels
- DAT SDK : `MWDATCore`, `MWDATCamera` (Swift Package)
- WebRTC : package `WebRTC` (GoogleWebRTC)
- iOS minimum : 16.0

## Arborescence des sources

```
CameraAccess/
├── CameraAccessApp.swift          ← @main, init SDK, DebugMenu (DEBUG only)
│
├── Settings/
│   ├── SettingsManager.swift      ← singleton UserDefaults, fallback Secrets.swift
│   └── SettingsView.swift
│
├── Gemini/
│   ├── GeminiConfig.swift         ← constantes + isConfigured + websocketURL()
│   ├── GeminiLiveService.swift    ← WebSocket URLSessionWebSocketTask, états, callbacks
│   ├── GeminiSessionViewModel.swift ← orchestre audio/vidéo/tool calls
│   └── AudioManager.swift         ← AVAudioEngine capture + playback
│
├── OpenClaw/
│   ├── OpenClawBridge.swift       ← HTTP client (URLSession), session key, historique 10 turns
│   ├── ToolCallRouter.swift       ← route les function calls Gemini → OpenClaw
│   └── ToolCallModels.swift       ← structs : GeminiFunctionCall, ToolResult, ToolCallStatus
│
├── WebRTC/
│   ├── WebRTCConfig.swift         ← constantes, fetchIceServers() depuis /api/turn
│   ├── WebRTCClient.swift         ← RTCPeerConnection wrapper
│   ├── WebRTCSessionViewModel.swift ← orchestre signaling + connexion + mute
│   ├── SignalingClient.swift      ← WebSocket SDP/ICE exchange
│   ├── CustomVideoCapturer.swift  ← RTCVideoCapturer alimenté par UIImage
│   ├── RTCVideoView.swift         ← RTCEAGLVideoView wrapper SwiftUI
│   ├── PiPVideoView.swift         ← Picture-in-Picture (local + remote)
│   └── WebRTCOverlayView.swift    ← barre de statut WebRTC
│
├── iPhone/
│   └── IPhoneCameraManager.swift  ← AVCaptureSession caméra arrière (mode fallback)
│
├── ViewModels/
│   ├── WearablesViewModel.swift   ← enregistrement DAT SDK, état registration
│   ├── StreamSessionViewModel.swift ← StreamSession DAT, frames, photos, mode iPhone
│   ├── DebugMenuViewModel.swift   ← MockDeviceKit (DEBUG)
│   └── MockDeviceKit/
│       ├── MockDeviceKitViewModel.swift
│       └── MockDeviceViewModel.swift
│
└── Views/
    ├── CameraAccessApp.swift      ← (voir racine)
    ├── MainAppView.swift          ← routeur : HomeScreen ↔ StreamSessionView
    ├── HomeScreenView.swift       ← onboarding + boutons connexion/iPhone
    ├── RegistrationView.swift     ← flow d'enregistrement DAT SDK
    ├── StreamSessionView.swift    ← crée tous les ViewModels enfants, ZStack principal
    ├── StreamView.swift           ← vue plein écran pendant le stream
    ├── NonStreamView.swift        ← écran d'attente (avant stream)
    ├── PhotoPreviewView.swift     ← prévisualisation + partage photo capturée
    ├── DebugMenuView.swift        ← (DEBUG only)
    ├── Components/
    │   ├── CircleButton.swift
    │   ├── CustomButton.swift
    │   ├── CardView.swift
    │   ├── StatusText.swift
    │   ├── MediaPickerView.swift  ← UIImagePickerController bridge
    │   └── GeminiOverlayView.swift ← transcripts, ToolCallStatusView, SpeakingIndicator
    └── MockDeviceKit/
        ├── MockDeviceKitView.swift
        ├── MockDeviceCardView.swift
        └── MockDeviceKitButton.swift
```

## ViewModels — relations et responsabilités

### `WearablesViewModel`
- Observe `wearables.registrationStateStream()` et `wearables.devicesStream()`
- Propriétés clés : `registrationState`, `devices`, `hasMockDevice`, `skipToIPhoneMode`
- Méthodes : `connectGlasses()`, `disconnectGlasses()`
- Gère `showGettingStartedSheet` (première connexion)

### `StreamSessionViewModel`
- Crée et gère un `StreamSession` DAT SDK (résolution, codec, framerate 24fps)
- Modes : `.glasses` (DAT) ou `.iPhone` (IPhoneCameraManager)
- Propriétés clés : `currentVideoFrame`, `streamingStatus`, `hasActiveDevice`, `selectedResolution`
- Distribue les frames vers : `geminiSessionVM`, `webrtcSessionVM`
- Capture photo → `showPhotoPreview = true` + `capturedPhoto`
- Expose : `geminiSessionVM`, `webrtcSessionVM` (wired depuis `StreamSessionView`)

### `GeminiSessionViewModel`
- Gère le cycle de vie complet : audio setup → WebSocket → mic capture
- iPhone mode : mute mic pendant que le modèle parle (pas d'annulation d'écho)
- Propriétés clés : `isGeminiActive`, `connectionState`, `userTranscript`, `aiTranscript`, `toolCallStatus`
- Envoie les frames vidéo throttlées à 1fps via `sendVideoFrameIfThrottled()`
- Délègue les tool calls à `ToolCallRouter` → `OpenClawBridge`

### `WebRTCSessionViewModel`
- États : `disconnected → connecting → waitingForPeer → connected → backgrounded`
- Fetch TURN credentials depuis `/api/turn` sur le serveur de signaling
- `roomCode` persisté pour reconnexion après mise en arrière-plan
- Propriétés clés : `isActive`, `connectionState`, `roomCode`, `remoteVideoTrack`

## États et machines d'état

```
Registration:   unregistered → registering → registered
Streaming:      stopped → waiting → streaming
Gemini:         disconnected → connecting → settingUp → ready → error
WebRTC:         disconnected → connecting → waitingForPeer → connected → backgrounded → error
```

## Configuration et secrets

```swift
// Secrets.swift (gitignored) — copier depuis Secrets.swift.example
enum Secrets {
  static let geminiAPIKey = "YOUR_GEMINI_API_KEY"
  static let openClawHost = "http://YOUR_MAC_HOSTNAME.local"
  static let openClawPort = 5000
  static let openClawHookToken = "YOUR_OPENCLAW_HOOK_TOKEN"
  static let openClawGatewayToken = "YOUR_OPENCLAW_GATEWAY_TOKEN"
  static let webrtcSignalingURL = "ws://YOUR_MAC_IP:8080"
}
```

`SettingsManager.shared` lit depuis `UserDefaults`, avec fallback sur `Secrets`.
Tout est modifiable à l'écran `SettingsView` (onglet engrenage).

## Gemini Live — détails protocole

- WebSocket : `wss://generativelanguage.googleapis.com/ws/.../BidiGenerateContent?key=<API_KEY>`
- Modèle : `models/gemini-2.5-flash-native-audio-preview-12-2025`
- Audio in : 16kHz, 16-bit mono PCM
- Audio out : 24kHz, 16-bit mono PCM
- Vidéo : JPEG qualité 0.5, 1 frame/seconde
- Tool exposé : `execute(task: String)` — délègue à OpenClaw

## OpenClaw — détails protocole

- HTTP POST vers `{host}:{port}/gateway`
- Headers : `Authorization: Bearer {gatewayToken}`, `x-openclaw-session-key: agent:main:glass:{ISO8601}`
- Historique limité à 10 turns (sliding window)
- États connexion : `notConfigured → checking → connected → unreachable`

## WebRTC — détails

- Signaling WebSocket custom (SDP offer/answer + ICE candidates)
- STUN : `stun.l.google.com:19302`, `stun1.l.google.com:19302`
- TURN : fetch depuis `/api/turn` (format `iceServers` ou plat)
- Bitrate max : 2.5 Mbps, 24 fps
- `CustomVideoCapturer` : injecte les `UIImage` comme `RTCVideoFrame`

## Ajouter un fichier Swift

1. Créer le fichier dans le bon dossier
2. Dans `project.pbxproj`, ajouter :
   - Une entrée `PBXFileReference`
   - Une entrée `PBXBuildFile`
   - Le fichier dans le `PBXGroup` correspondant (ViewModels ou Views)
   - Le fichier dans la section `PBXSourcesBuildPhase` (Sources)

## Compilation conditionnelle

```swift
#if canImport(MWDATMockDevice)   // MockDevice dispo en DEBUG / simulator
#if DEBUG                        // debug menu overlay
```

## Points d'attention

- `geminiVM` et `webrtcVM` sont mutuellement exclusifs (conflit audio) — le bouton de l'un
  est désactivé quand l'autre est actif (`StreamView.ControlsView`)
- La capture photo n'est disponible qu'en mode `.glasses` (DAT SDK `capturePhoto()`)
- `StreamSessionViewModel.stopSession()` délègue à `stopIPhoneSession()` si mode iPhone
- `UIApplication.shared.isIdleTimerDisabled = true` pendant tout le streaming
