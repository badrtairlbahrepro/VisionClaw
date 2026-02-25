# CameraAccess Android — Contexte détaillé

> Lire aussi : `/home/user/VisionClaw/CLAUDE.md` pour le contexte global.

## Stack technique

- **Kotlin**, **Jetpack Compose**, **Material3**
- Pattern **MVVM** : `AndroidViewModel` + `MutableStateFlow` / `StateFlow`
- Navigation : logique conditionnelle dans `CameraAccessScaffold` (pas de NavController)
- minSdk 31, targetSdk 34, compileSdk 35
- DAT SDK : `mwdat.core`, `mwdat.camera`, `mwdat.mockdevice`
- WebRTC : `libs.webrtc`
- HTTP : OkHttp, Gson
- CameraX pour le mode téléphone
- DataStore Preferences (remplacement de SharedPreferences)

## Package racine

```
com.meta.wearable.dat.externalsampleapps.cameraaccess
```

## Arborescence des sources

```
cameraaccess/
├── MainActivity.kt                ← permissions, init DAT SDK, setContent
│
├── ui/
│   ├── CameraAccessScaffold.kt    ← routeur principal : Home ↔ NonStream ↔ Stream ↔ Settings
│   ├── HomeScreen.kt              ← onboarding + boutons connexion/téléphone
│   ├── NonStreamScreen.kt         ← avant stream (device status, qualité, bouton start)
│   ├── StreamScreen.kt            ← plein écran pendant le stream
│   ├── SettingsScreen.kt          ← clés API et configuration
│   ├── GeminiOverlayView.kt       ← transcripts, outil status, indicateur parole
│   ├── WebRTCOverlayView.kt       ← état WebRTC + room code
│   ├── SharePhotoDialog.kt        ← dialog partage photo
│   ├── CircleButton.kt
│   ├── ControlsRow.kt             ← boutons Stop / Photo / AI / Live pendant le stream
│   ├── SwitchButton.kt
│   ├── AppColor.kt                ← couleurs Material3
│   └── MockDeviceKitScreen.kt     ← UI MockDevice (DEBUG)
│
├── wearables/
│   ├── WearablesViewModel.kt      ← enregistrement DAT, device discovery, permissions
│   └── WearablesUiState.kt        ← data class état UI
│
├── stream/
│   ├── StreamViewModel.kt         ← StreamSession DAT, frames Bitmap, photos, mode téléphone
│   └── StreamUiState.kt
│
├── gemini/
│   ├── GeminiConfig.kt            ← constantes (même config que iOS)
│   ├── GeminiLiveService.kt       ← WebSocket OkHttp, callbacks
│   ├── GeminiSessionViewModel.kt  ← orchestre audio/vidéo/tool calls
│   └── AudioManager.kt            ← AudioRecord + AudioTrack
│
├── openclaw/
│   ├── OpenClawBridge.kt          ← HTTP OkHttp, session key, historique 10 turns
│   ├── ToolCallRouter.kt
│   └── ToolCallModels.kt
│
├── webrtc/
│   ├── WebRTCConfig.kt
│   ├── WebRTCClient.kt
│   ├── WebRTCSessionViewModel.kt
│   ├── SignalingClient.kt
│   └── CustomVideoCapturer.kt     ← injecte des Bitmap dans le flux WebRTC
│
├── phone/
│   └── PhoneCameraManager.kt      ← CameraX (camera arrière, mode fallback)
│
├── settings/
│   └── SettingsManager.kt         ← DataStore Preferences, fallback Secrets.kt
│
└── mockdevicekit/
    ├── MockDeviceKitViewModel.kt
    └── MockDeviceKitUiState.kt
```

## Navigation (CameraAccessScaffold)

```kotlin
when {
  uiState.isSettingsVisible -> SettingsScreen
  uiState.isStreaming        -> StreamScreen
  uiState.isRegistered       -> NonStreamScreen
  else                       -> HomeScreen
}
```

Pas de `NavController` — la navigation est pilotée par l'état du ViewModel.

## ViewModels — responsabilités

### `WearablesViewModel` (AndroidViewModel)
- `AutoDeviceSelector` pour détecter automatiquement le device actif
- Observe `Wearables.registrationState` et `Wearables.devices`
- Méthodes : `startRegistration()`, `startUnregistration()`, `navigateToDeviceSelection()`
- Gère `isGettingStartedSheetVisible`, `hasActiveDevice`, `recentError`

### `StreamViewModel` (AndroidViewModel)
- `Wearables.startStreamSession()` avec `StreamConfiguration(VideoQuality.MEDIUM, 24fps)`
- Modes : `StreamingMode.GLASSES` ou `StreamingMode.PHONE`
- Distribue les frames vers `geminiViewModel` et `webrtcViewModel`
- Partage photos via `FileProvider` + `Intent.ACTION_SEND`
- Retour auto vers NonStreamScreen quand `StreamSessionState.STOPPED`

### `GeminiSessionViewModel` (ViewModel)
- Même logique que iOS : WebSocket + AudioRecord + tool calls
- iPhone mode : mute mic pendant que le modèle parle
- `sendVideoFrameIfThrottled(Bitmap)` : 1 frame/seconde

### `WebRTCSessionViewModel` (ViewModel)
- Même machine d'état que iOS : `disconnected → connecting → waitingForPeer → connected`
- Reconnexion automatique après passage en arrière-plan

## Pattern de données

```kotlin
// Exposition de l'état
private val _uiState = MutableStateFlow(StreamUiState())
val uiState: StateFlow<StreamUiState> = _uiState.asStateFlow()

// Mise à jour
_uiState.update { it.copy(isStreaming = true) }

// Collecte dans Compose
val uiState by viewModel.uiState.collectAsStateWithLifecycle()
```

## Configuration et secrets

```kotlin
// Secrets.kt (gitignored) — copier depuis Secrets.kt.example
object Secrets {
  const val GEMINI_API_KEY = "YOUR_GEMINI_API_KEY"
  const val OPENCLAW_HOST = "http://YOUR_MAC_HOSTNAME.local"
  const val OPENCLAW_PORT = 5000
  const val OPENCLAW_HOOK_TOKEN = "YOUR_OPENCLAW_HOOK_TOKEN"
  const val OPENCLAW_GATEWAY_TOKEN = "YOUR_OPENCLAW_GATEWAY_TOKEN"
  const val WEBRTC_SIGNALING_URL = "ws://YOUR_MAC_IP:8080"
}
```

`SettingsManager` utilise DataStore Preferences, avec fallback sur `Secrets`.

## Build

```bash
# Depuis samples/CameraAccessAndroid/
./gradlew assembleDebug
./gradlew installDebug
```

Le keystore de debug (`sample.keystore`) est inclus dans le dépôt pour faciliter le build.

GitHub Packages nécessite une `github_token` dans `gradle.properties` (ou `~/.gradle/gradle.properties`) pour télécharger le SDK DAT :
```properties
github_token=ghp_...
```

## Parité iOS ↔ Android

Les deux apps sont fonctionnellement identiques :
- Même protocole Gemini Live (WebSocket, même modèle)
- Même protocole OpenClaw (HTTP, même format de session key)
- Même logique WebRTC (STUN/TURN, signaling custom)
- Même configuration via `GeminiConfig` / `WebRTCConfig`

Différences techniques :
| Aspect | iOS | Android |
|---|---|---|
| Reactive state | `@Published` + Combine | `StateFlow` |
| Main thread | `@MainActor` | `Dispatchers.Main` |
| Camera fallback | `AVCaptureSession` | CameraX |
| Storage config | `UserDefaults` | DataStore Preferences |
| WebSocket | `URLSessionWebSocketTask` | OkHttp WebSocket |
| HTTP | `URLSession` | OkHttp |

## Points d'attention

- `CameraAccessScaffold` reçoit `onRequestWearablesPermission` depuis `MainActivity` — ne pas
  gérer les permissions Wearables depuis un ViewModel
- `StreamViewModel` dépend de `WearablesViewModel.deviceSelector` — toujours passer
  le `WearablesViewModel` en paramètre du factory
- Les photos sont enregistrées dans le cache interne (`cacheDir/photos/`) et partagées
  via `FileProvider` (déclaré dans `AndroidManifest.xml`)
- Gemini et WebRTC sont mutuellement exclusifs (conflit audio) — désactiver l'un avant
  d'activer l'autre
