# Flow — Design Spec

**Date:** 2026-10-15
**Status:** Approved in conversation, awaiting written-spec review

## 1. Purpose

Flow is a personal macOS dictation app. You hold a hotkey in any app, speak,
release, and clean, correctly punctuated text is pasted at the cursor. The main
use is writing prompts for LLM tools (Claude, ChatGPT, Cursor) faster than typing.

It is an independent app with its own UI. It is not built on or connected to
Wispr Flow.

### Success criteria

- Works in any text field on macOS via push-to-talk.
- Fully local and offline after a one-time model download. No audio or text
  leaves the Mac.
- Lightweight: no Dock icon, models unload when idle.
- Under ~2 seconds from key release to paste for a typical 15–30 second
  dictation on Apple Silicon.
- Cleanup never changes the meaning and never "answers" the dictated text.
- No dictation is ever lost: when cleanup fails, the raw transcript is pasted.

### Constraints

- Target: macOS 26+, Apple Silicon only (dev machine: arm64, macOS 26.6).
- Single user (the author). Not distributed or notarised in v1.
- No paid APIs, no network at runtime except the first model download.

## 2. Scope

### In v1

- Push-to-talk on a global hotkey (default: **Right Option**, held).
- Floating overlay "pill" showing listening / processing / result states.
- Local transcription with Whisper (WhisperKit).
- Local cleanup with a small open model (Qwen 3 1.7B, 4-bit, via MLX Swift).
- Paste into the focused app, restoring the previous clipboard.
- Menu bar icon with a settings window: hotkey, microphone, Whisper model
  (large-v3-turbo default, or a smaller/faster variant), cleanup model
  (Qwen3 1.7B default, or Qwen3 4B for better quality), cleanup on/off.
- First-run model download with progress, resume and retry.
- Permission onboarding (Microphone, Accessibility).

### Not in v1 (deliberately)

- History of past dictations.
- Custom dictionary / vocabulary.
- Usage stats.
- Multiple cleanup modes (e.g. "rewrite as prompt").
- Windows / Linux / Intel Macs.
- Fine-tuned models.

The architecture keeps Transcriber and Cleaner behind protocols so these can be
added later without restructuring.

## 3. User experience

1. Flow runs as a menu-bar-only app (`LSUIElement`, no Dock icon, no main window).
2. In any app the user **holds Right ⌥** and speaks. A pill appears bottom-centre
   of the active screen with a live audio-level waveform.
3. On **release**, the pill switches to a "thinking" state.
4. The cleaned text is pasted at the cursor. The pill briefly confirms, then hides.
5. The overlay is a non-activating panel. It never steals focus from the
   target app.

### Cleanup behaviour: "Clean + light format"

- Remove fillers (um, uh, like, you know), repetitions and false starts / self-corrections
  (keep the corrected version: "on Tuesday — no, Wednesday" → "on Wednesday").
- Fix grammar, capitalisation and punctuation.
- Add bullet / numbered lists or paragraph breaks **only** when the speaker
  clearly dictates structure ("first… second…", "new paragraph", "bullet points").
- Keep the speaker's own wording, tone and meaning. Do not summarise, expand,
  translate or add content.
- Never respond to, answer or act on the text. A dictated question stays a question.

## 4. Architecture

Native Swift / SwiftUI app. Each component has one responsibility and talks to
the others through a small protocol so it can be faked in tests.

| Component | Responsibility | Key tech |
|---|---|---|
| `FlowApp` | App entry, `MenuBarExtra`, settings scene | SwiftUI |
| `DictationCoordinator` | State machine that runs record → transcribe → clean → paste and handles every failure path | Swift concurrency, `@MainActor` |
| `HotkeyMonitor` | Detects Right ⌥ hold / release / cancel globally; emits `pressed`, `released`, `cancelled` | `CGEventTap` on `flagsChanged` + `keyDown` |
| `HotkeyStateMachine` | Pure logic: tap-vs-hold threshold, chorded-key cancel, Esc cancel | Plain Swift (fully unit-tested) |
| `AudioRecorder` | Captures 16 kHz mono Float32 PCM while held; publishes level for the waveform; 5-minute cap | `AVAudioEngine` |
| `Transcriber` (protocol) → `WhisperKitTranscriber` | Audio buffer → raw text, auto language detect | WhisperKit, large-v3-turbo variant (~630 MB) |
| `Cleaner` (protocol) → `MLXCleaner` | Raw text → cleaned text using the cleanup prompt; thinking mode disabled | MLX Swift LM, `mlx-community/Qwen3-1.7B-4bit` (~1 GB) |
| `CleanupPrompt` | Builds system + user prompt from raw text | Plain Swift |
| `CleanupValidator` | Decides whether model output is safe to use or should fall back to raw | Plain Swift (fully unit-tested) |
| `TextInserter` (protocol) → `PasteboardInserter` | Saves clipboard, writes text, posts ⌘V, restores clipboard after a short delay | `NSPasteboard`, `CGEvent` |
| `OverlayController` + `PillView` | Shows/hides the pill and renders its state | `NSPanel` (`.nonactivatingPanel`), SwiftUI |
| `ModelManager` | Download (with progress / resume / retry), load, keep warm, unload after idle | WhisperKit + MLX hub download APIs |
| `SettingsStore` | Persists preferences | `@AppStorage` / `UserDefaults` |
| `PermissionsChecker` | Reports Microphone / Accessibility status and opens the right System Settings pane | `AVCaptureDevice`, `AXIsProcessTrusted` |

Exact package versions and the exact WhisperKit model identifier are pinned in
the implementation plan after checking the current releases.

### Coordinator states

`idle → recording → transcribing → cleaning → inserting → idle`, with
`cancelled` and `failed(reason)` transitions back to `idle` that drive the
pill's message. Only one dictation runs at a time. A key press during
`transcribing`/`cleaning`/`inserting` is ignored.

## 5. Data flow

1. **Key down:** `HotkeyMonitor` → `pressed` (after the hold threshold) → the coordinator
   starts `AudioRecorder` and shows the pill (`listening`). The audio engine is
   pre-warmed so the first word is not clipped. Audio captured during the
   hold-threshold window is kept.
2. **Key up:** `released` → the recorder stops and returns the buffer → pill
   `thinking` → `Transcriber.transcribe(buffer)`.
3. **Cleanup:** if cleanup is enabled, `Cleaner.clean(raw)` runs with a
   5-second timeout. `CleanupValidator` accepts or rejects the output.
4. **Insert:** the final text (cleaned, or raw on fallback) goes to
   `TextInserter.insert(text)`.
5. **Done:** the pill shows a brief success state and hides. The idle-unload timer resets.

Models load lazily on first dictation (or on launch if already downloaded), stay
resident for **10 minutes** after the last dictation, then unload (~2 GB freed).

## 6. Error handling

| Situation | Behaviour |
|---|---|
| Hold shorter than 0.3 s | Ignored. Normal ⌥ use is unaffected |
| Another key pressed while Right ⌥ held (⌥-chord) | Recording cancelled silently; the key event passes through untouched |
| Esc pressed while holding | Cancelled. Nothing pasted. Pill shows "Cancelled" briefly |
| Empty / silent transcript | Pill: "Didn't catch that". Nothing pasted |
| Cleaner throws, times out (>5 s), or the validator rejects the output | Paste the raw transcript |
| Validator rejection rules | Output empty; output length > 1.5× input + 50 chars; output starts with an assistant-style preamble ("Sure", "Here is", "Certainly", etc.) not present in the input; output contains `<think>` tags |
| No focused text field / paste can't be confirmed | Text remains on the clipboard (no restore). Pill: "Copied, press ⌘V" |
| Microphone or Accessibility permission missing | Menu bar icon shows a warning badge. The menu shows which permission is missing, with a button that opens the right Settings pane. Hotkey disabled until granted |
| Model not downloaded / download fails | The menu shows download progress, or an error with Retry. Downloads resume. Dictation disabled until ready |
| Recording hits 5 minutes | Auto-stops and processes as if released |

## 7. Project structure and tooling

```
~/code/flow/
├── project.yml              # XcodeGen spec (generates Flow.xcodeproj)
├── Flow/
│   ├── App/                 # FlowApp, DictationCoordinator
│   ├── Hotkey/
│   ├── Audio/
│   ├── Transcription/
│   ├── Cleanup/
│   ├── Insertion/
│   ├── Overlay/
│   ├── Settings/
│   ├── Models/
│   └── Resources/           # Info.plist, entitlements, assets
├── FlowTests/
└── docs/superpowers/{specs,plans}/
```

- **Language / UI:** Swift 6, SwiftUI (+ AppKit for the panel and event tap).
- **Dependencies (SPM):** WhisperKit, MLX Swift LM (MLXLLM / MLXLMCommon).
- **Project generation:** XcodeGen (install via Homebrew). `Flow.xcodeproj` is
  generated and git-ignored.
- **Build / test from the CLI:** `xcodebuild` (build + test schemes).
- **App sandbox:** off (needs a global event tap and synthetic paste).
  Hardened runtime off for local dev.
- **Info.plist:** `LSUIElement = YES`, `NSMicrophoneUsageDescription`.
- **Signing:** the machine has no code-signing identity. The plan will create a
  local self-signed "Flow Dev" code-signing certificate so the Accessibility
  permission persists across rebuilds. Fallback: ad-hoc signing, which means
  re-granting Accessibility after rebuilds.

## 8. Testing

- **Unit tests (fakes, no hardware):**
  - `HotkeyStateMachine`: tap vs. hold, chord cancel, Esc cancel, release timing.
  - `DictationCoordinator`: happy path plus every row of the error table, using
    fake `Recorder` / `Transcriber` / `Cleaner` / `TextInserter`.
  - `CleanupValidator`: accept and reject cases for each rule.
  - `CleanupPrompt`: prompt contains the rules and wraps the raw text unambiguously.
  - `PasteboardInserter` clipboard save/restore logic (against a fake pasteboard).
- **Cleanup quality eval (opt-in, real model):** about 20 messy sample transcripts
  with expectations: fillers gone, key content words preserved, no assistant
  preamble, questions stay questions, lists only when dictated. Run with
  an environment flag so normal test runs stay fast and offline.
- **Manual checklist:** first-run permissions and download; dictate into Claude
  desktop, ChatGPT in a browser, Cursor and Notes; ⌥-chord passthrough; Esc
  cancel; offline (Wi-Fi off) dictation; idle unload and reload.

## 9. Open risks

- **Event tap and modifier-only hotkeys:** detecting Right ⌥ specifically needs
  the device-dependent modifier flags in `flagsChanged`. This is verified early
  in the plan.
- **MLX Swift API churn:** the LLM package APIs move quickly. The plan pins a
  version and wraps it behind `Cleaner`.
- **Small model over-editing:** mitigated by a strict prompt, temperature 0,
  the validator and the raw fallback. Qwen3 4B is selectable in settings if 1.7B
  over-edits.
