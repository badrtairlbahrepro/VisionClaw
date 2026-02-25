# VisionClaw — Contexte projet

## Ce que c'est

VisionClaw est une application mobile (iOS + Android) qui connecte des lunettes
intelligentes Meta Ray-Ban (via le SDK DAT de Meta) à Gemini Live (IA vocale
temps réel) et à un serveur personnel appelé **OpenClaw**. L'objectif est un
assistant IA mains-libres : l'utilisateur parle, l'IA voit à travers les
lunettes, et peut déléguer des tâches à OpenClaw (envoyer des messages, faire
des recherches, gérer des listes…).

## Structure du dépôt

```
VisionClaw/
├── CLAUDE.md                  ← ce fichier
├── samples/
│   ├── CameraAccess/          ← app iOS (Swift/SwiftUI)
│   │   └── CLAUDE.md          ← contexte iOS détaillé
│   └── CameraAccessAndroid/   ← app Android (Kotlin/Compose)
│       └── CLAUDE.md          ← contexte Android détaillé
└── assets/                    ← ressources visuelles partagées
```

## Composants techniques clés

| Composant | Rôle |
|---|---|
| **DAT SDK** (`MWDATCore`, `MWDATCamera`) | Flux vidéo depuis les lunettes Ray-Ban |
| **Gemini Live** | WebSocket bidirectionnel vers `gemini-2.5-flash-native-audio-preview` |
| **OpenClaw** | Serveur local (Flask/HTTP) pour l'exécution de tâches via l'IA |
| **WebRTC** | Stream vidéo peer-to-peer vers un navigateur/appareil tiers |

## Flux de données principal

```
Lunettes Ray-Ban
  └─▶ DAT SDK (StreamSession)
        └─▶ StreamSessionViewModel  (frame UIImage / Bitmap)
              ├─▶ UI (affichage local)
              ├─▶ GeminiSessionViewModel  (1 frame/s en JPEG)
              │     ├─▶ GeminiLiveService (WebSocket)
              │     └─▶ OpenClawBridge   (HTTP)
              └─▶ WebRTCSessionViewModel (toutes les frames)
                    └─▶ WebRTCClient (P2P)
```

## Règles de développement

- Toujours travailler sur la branche désignée par la tâche (format `claude/<nom>-<id>`)
- iOS : MVVM strict, `@MainActor` sur tous les ViewModels, `@Published` + `ObservableObject`
- Android : MVVM avec `StateFlow`, `viewModelScope`
- Secrets (`Secrets.swift` / `Secrets.kt`) ne sont **jamais** commités — utiliser les fichiers `.example`
- Quand on ajoute un fichier Swift, l'enregistrer aussi dans `project.pbxproj`
  (sections PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase)

## Fichiers à ne pas modifier sans raison explicite

- `Secrets.swift` / `Secrets.kt.example`
- `CameraAccess.entitlements`
- Fichiers de package (`Package.resolved`, `build.gradle.kts`)
