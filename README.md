# CF15T Auxiliary Command Center (macOS)

A native macOS touch-first control panel and window tiling workstation built in Swift (`SwiftUI`, `AppKit`, `ApplicationServices`, `CoreAudio`) specifically optimized for the **Caperave (CaperaveTech) CF15T** 15.6-inch `1920×1080` (`141.2 PPI`) 10-point capacitive portable touchscreen monitor.

---

## Features

### 1. Center Stage + Perimeter Border Window Matrix (`WindowTilingEngine`)
- **Simultaneous Live Tiled View:** Displays all open macOS application windows at once with live snapshots (`CGWindowListCreateImage` + `CGWindowListCopyWindowInfo`).
- **Tap to Expand Center Stage:** Tapping any window tile along the perimeter border immediately expands it into the large **Center Stage** while keeping all remaining open windows arranged visibly around the border (left rail, right rail, and bottom strip).
- **Physical macOS Window Tiling (`AXUIElement`):** Automatically resizes and positions the actual macOS application windows on your target display (`Main Mac Screen`, `CF15T / External Screen`, or `Window's Current Screen`).
- **4 Layout Modes:**
  - **Center + Border** (`centerStageBorder`)
  - **Stage + Perimeter** (`leftStagePerimeter`)
  - **Equal Grid** (`equalSimultaneousGrid`)
  - **50/50 Voice Split** (`dualVoiceSplit`)
- **One-Tap Restore:** Restores all macOS windows to their original pre-tiled bounds at any time.

### 2. Grok Bot ⇄ Dot Voice Switcher & CoreAudio Mic Deck (`CoreAudioMicManager`)
- **Instant Ping-Pong Switch (`SWAP A ⇄ B`):** One-tap switching between **Slot A (`Grok Bot`)** and **Slot B (`Dot` / `Claude` / `ChatGPT` / Configurable)** with automatic window promotion and microphone handoff.
- **Per-Assistant Tactile Mic Toggles:** Oversized `MIC ON / MUTED` buttons that control hardware `CoreAudio` input mute (`kAudioDevicePropertyMute` / `kAudioDevicePropertyVolumeScalar`) and send the assistant's configured voice shortcut.
- **Exclusive Mic Lock:** Unmuting Slot A automatically mutes Slot B (and vice versa) so both voice assistants never talk over or listen to each other simultaneously.
- **Customizable Voice Slots (`VoiceSlotEditorSheet`):** Assign either slot to any installed app or URL (`Grok Bot`, `Dot`, `Claude`, `ChatGPT`, `Codex`, `Antigravity`, `Prism Live`, `Cubed Code`) and configure its push-to-talk/mute shortcut.

### 3. Multi-Platform AI Agent & Running Tasks Monitor (`AgentAndTaskMonitor`)
- **AI Agent Platforms:** Monitors live execution status (`WORKING`, `READY`, or `OFFLINE`), CPU %, memory footprint, and active window/subtask across **Grok Bot**, **Dot**, **Claude**, **Codex**, **Antigravity**, **ChatGPT**, **Cubed Code**, **Bomb Code**, **Ollama**, and **Prism / Pillar**.
- **Running Tasks Feed:** Lists active background developer and CLI processes (`claude`, `codex`, `node`, `python`, `swift`, etc.) sorted by live CPU utilization.

### 4. CF15T Touchscreen Ergonomics (`CursorSnapbackEngine`)
- **Automatic Touch Cursor Snapback:** Prevents touches on the secondary CF15T touchscreen from stealing the mouse pointer away from your primary MacBook display (`CGWarpMouseCursorPosition`).
- **No-Hover High-Contrast Dark UI:** Engineered for a `141.2 PPI` capacitive touchscreen with oversized tap targets (`>= 52pt`) and zero hover-only controls.
- **One-Tap Move to CF15T:** Snaps the Command Center window directly onto the external `1920×1080` touchscreen.

---

## Building & Running

```zsh
./build_app.sh
open "CF15T Command Center.app"
```

### Required macOS Permissions
- **Accessibility** (*System Settings → Privacy & Security → Accessibility*): Required to physically move and resize external application windows via `AXUIElement`.
- **Screen Recording** (*System Settings → Privacy & Security → Screen & System Audio Recording*): Optional; enables live pixel previews of other apps' windows inside the Command Center matrix.
