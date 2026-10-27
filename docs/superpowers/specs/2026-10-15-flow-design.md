# Flow — Design Spec

**Date:** 2026-10-15
**Status:** Approved (2026-10-15). Amended same day after the UI round: ⌥→ default hotkey, tap-to-toggle + hold-to-talk, notch overlay (see §11).

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

- Push-to-talk on a global hotkey (default: **Right Option**, held), changeable
  at any time from settings via a "Record shortcut" field (see §3.2).
- Floating overlay "pill" showing listening / processing / result states.
- Local transcription with Whisper (WhisperKit).
- Local cleanup with a small open model (Qwen 3 1.7B, 4-bit, via MLX Swift).
- Paste into the focused app, restoring the previous clipboard.
- Menu bar icon with a settings window: hotkey recorder, microphone, Whisper model
  (large-v3-turbo default, or a smaller/faster variant), cleanup model
  (Qwen3 1.7B default, or Qwen3 4B for better quality), cleanup on/off,
  keep-warm time (2 min / **10 min default** / 30 min / Always).
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

### 3.1 Dictation

1. Flow runs as a menu-bar-only app (`LSUIElement`, no Dock icon, no main window).
2. In any app the user **holds the hotkey** (default Right ⌥) and speaks. A pill appears bottom-centre
   of the active screen with a live audio-level waveform.
3. On **release**, the pill switches to a "thinking" state.
4. The cleaned text is pasted at the cursor. The pill briefly confirms, then hides.
5. The overlay is a non-activating panel. It never steals focus from the
   target app.

### 3.2 Changing the hotkey

- Settings has a **"Record shortcut"** field. Click it, press the desired key or
  combo, and it is saved and applied immediately (no restart).
- Supported shortcuts:
  - **Single modifier held alone:** Right ⌥, Left ⌥, Right ⌘, Right ⌃, Right ⇧,
    Fn/🌐. Side-specific where macOS reports it.
  - **Combo:** one or more modifiers plus one key (e.g. ⌃Space, ⌥⌘D). The combo's
    key-down events are swallowed so they don't also type into the target app.
- Rejected / warned: plain letter or number keys with no modifier (rejected);
  combos that clash with well-known system shortcuts such as ⌘Space, ⌘Tab
  or ⌘Q (warning, user can still save). Fn/🌐 shows a note to set
  System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing".
- "Reset to default" button restores Right ⌥.
- The hotkey is stored as a `Hotkey` value (`modifierOnly(key)` or
  `combo(modifiers, keyCode)`) in `SettingsStore`. `HotkeyMonitor` and
  `HotkeyStateMachine` take a `Hotkey` value instead of a hard-coded key, and
  re-arm when it changes.

### 3.3 UI iteration workflow

The pill and settings window will be refined over several rounds with the user.
The design supports quick iteration:

- **Mockups first.** Before building the pill or settings UI, show 2–3 visual
  options as browser mockups. The user picks one and requests tweaks. Native
  SwiftUI is built only from the chosen mockup.
- **One theme file.** All visual constants (colours, sizes, corner radii, fonts,
  waveform style, animation timings, pill position) live in `Theme.swift`. No
  magic numbers in views.
- **Previews for every state.** `PillView` has an Xcode `#Preview` for each
  state (listening, thinking, success, cancelled, didn't-catch-that, copied,
  error). The settings window has one too.
- **UI playground (Debug builds only).** A menu bar item "UI Playground" drives
  the real overlay through every state on screen, with a fake waveform, without
  recording or loading models.
- **Review checkpoint after each UI round.** The user tries it and gives
  feedback before more work continues.

### 3.4 Cleanup behaviour: "Clean + light format"

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
| `Hotkey` | Value type for the configured shortcut (modifier-only or combo); Codable | Plain Swift |
| `HotkeyMonitor` | Detects the configured hotkey's hold / release / cancel globally; re-arms when settings change; emits `pressed`, `released`, `cancelled` | `CGEventTap` on `flagsChanged` + `keyDown` |
| `HotkeyStateMachine` | Pure logic for a given `Hotkey`: tap-vs-hold threshold, chorded-key cancel, Esc cancel |
| `HotkeyRecorderView` | Settings field that captures a new shortcut and validates it | SwiftUI + local `NSEvent` monitor | Plain Swift (fully unit-tested) |
| `AudioRecorder` | Captures 16 kHz mono Float32 PCM while held; publishes level for the waveform; 5-minute cap | `AVAudioEngine` |
| `Transcriber` (protocol) → `WhisperKitTranscriber` | Audio buffer → raw text, auto language detect | WhisperKit, large-v3-turbo variant (~630 MB) |
| `Cleaner` (protocol) → `MLXCleaner` | Raw text → cleaned text using the cleanup prompt; thinking mode disabled | MLX Swift LM, `mlx-community/Qwen3-1.7B-4bit` (~1 GB) |
| `CleanupPrompt` | Builds system + user prompt from raw text | Plain Swift |
| `CleanupValidator` | Decides whether model output is safe to use or should fall back to raw | Plain Swift (fully unit-tested) |
| `TextInserter` (protocol) → `PasteboardInserter` | Saves clipboard, writes text, posts ⌘V, restores clipboard after a short delay | `NSPasteboard`, `CGEvent` |
| `Theme` | All visual constants for the pill and settings | Plain Swift |
| `UIPlayground` (Debug only) | Menu item that drives the overlay through every state | SwiftUI |
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
resident for the **keep-warm time** after the last dictation (default 10 minutes;
2 / 10 / 30 min or Always in settings), then unload (~2 GB freed). Each dictation
resets the timer.

## 6. Error handling

| Situation | Behaviour |
|---|---|
| Hold shorter than 0.3 s (modifier-only hotkey) | Ignored. Normal use of that key is unaffected |
| Another key pressed while a modifier-only hotkey is held (e.g. ⌥-chord) | Recording cancelled silently; the key event passes through untouched |
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
  - `HotkeyStateMachine`: tap vs. hold, chord cancel, Esc cancel, release timing,
    for both modifier-only and combo hotkeys.
  - `Hotkey`: Codable round-trip, display string ("Right ⌥", "⌃Space"),
    validation (rejects bare keys, warns on system clashes).
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
  desktop, ChatGPT in a browser, Cursor and Notes; change the hotkey to a combo
  and back; ⌥-chord passthrough; Esc
  cancel; offline (Wi-Fi off) dictation; idle unload and reload.

## 9. Open risks

- **Event tap and modifier-only hotkeys:** detecting a specific side (e.g.
  Right ⌥) needs the device-dependent modifier flags in `flagsChanged`. This is verified early
  in the plan.
- **MLX Swift API churn:** the LLM package APIs move quickly. The plan pins a
  version and wraps it behind `Cleaner`.
- **Small model over-editing:** mitigated by a strict prompt, temperature 0,
  the validator and the raw fallback. Qwen3 4B is selectable in settings if 1.7B
  over-edits.
- **Fn/🌐 key:** macOS may trigger the emoji picker or dictation. Handled by a
  settings note rather than code.

## 10. Build phases (outline for the implementation plan)

0. **Setup:** XcodeGen, "Flow Dev" signing cert, skeleton menu bar app + test
   target, pin WhisperKit / MLX versions.
1. **Core logic (test-first, no hardware):** `Hotkey`, `HotkeyStateMachine`,
   `CleanupValidator`, `CleanupPrompt`, `DictationCoordinator` with fakes.
2. **Real input/output:** `HotkeyMonitor` (configurable), `AudioRecorder`,
   `PasteboardInserter`. Checkpoint: hold, talk, release pastes placeholder text.
3. **UI round 1:** browser mockups of the pill → user picks → `Theme`,
   `PillView` + previews, `OverlayController`, UI Playground. Review checkpoint.
4. **AI:** `ModelManager`, `WhisperKitTranscriber`, `MLXCleaner`, cleanup
   quality eval. Checkpoint: fully working offline dictation.
5. **Settings + UI round 2:** settings window mockups → user picks →
   settings window incl. `HotkeyRecorderView`, permissions onboarding.
   Review checkpoint.
6. **Polish:** manual test pass, UI tweaks from feedback, README.

## 11. Amendments (2026-10-15, after UI round 1)

These override earlier sections where they conflict.

1. **Default hotkey: ⌥→ (Option + Right Arrow).** The user's choice, accepting that ⌥→
   ("jump one word right") no longer works in text fields. ⌥⇧→ (select word) and plain →
   are unaffected because modifiers must match exactly. Still changeable in Settings.
2. **Tap to toggle + hold to talk** (replaces "hold shorter than 0.3 s is ignored"):
   - Quick press (< 0.3 s) starts **hands-free** recording; the next press stops it and pastes.
   - Holding (≥ 0.3 s) is **push-to-talk**; releasing stops it and pastes.
   - While the key is physically down, another key or a click cancels (⌥E, ⌥-click).
     In hands-free mode, clicks and typing are ignored (so the user can click the text box
     they want the text pasted into). **Esc** cancels in every mode.
   - If recording hits the 5-minute cap in hands-free mode, the hotkey un-latches so the next
     press starts a new dictation.
3. **Overlay: Midnight Capsule in the notch ("Slim Wings", A1 Calm Scroll).** Replaces the
   bottom-centre pill. A black shape grows out of the MacBook notch (340 × 34 pt) with the
   waveform in the left wing and the recording dot + timer in the right wing. Exact values:
   `docs/mockups/pill-decision.md`. Always shown on the **built-in (notched) display**, even
   when working on an external monitor. If the built-in display is off (lid closed), it hangs
   from the top-centre of the main screen with the same look.
4. **Waveform reacts to loudness** (RMS → 0…1 over −50…0 dBFS), sampled every 120 ms with
   smoothing 0.55 and a 180 ms ease, so quiet speech draws short bars and loud speech tall ones.
5. **English-only transcription (2026-10-16, latency).** The user only dictates English, so Whisper runs
   with `language: "en"` and language detection off (the language token is still prefilled). This replaces
   "auto language detect" in §4. `WhisperKitTranscriber(language:)` takes the code (nil = auto-detect)
   so it can become a setting later.
6. **Light cleanup for short phrases (2026-10-16, latency, user-approved).** When cleanup is on and the
   normalized transcript has fewer than 8 words (`DictationCoordinator.quickCleanupWordLimit`), the model is
   skipped and the rule-based `QuickCleaner` runs instead (no validator): it drops standalone fillers
   (um, uh, er, erm, hmm, mm), collapses immediate stutters ("i i think" → "I think"), capitalises "I" and
   the first word, and ends the text with `.`, or `?` when it starts with a question word. If nothing is
   left, the pill shows "Didn't catch that" and nothing is pasted.
7. **Pause media while dictating (2026-10-18, user-approved).** When a dictation starts, Flow pauses the
   Spotify app if it is playing and any playing `<video>`/`<audio>` in Chrome tabs (YouTube, Netflix, HBO).
   Already-paused media is left alone. When the dictation ends (pasted, cancelled, no speech, error, or the
   mic failed to open) it resumes only what it paused, and skips anything the user already resumed. Plain
   resume, no fades or rewind. Always on, no setting. `SystemMediaPauser` runs AppleScript via `osascript`
   on a serial background queue so the hotkey never waits. Needs Automation permission for Spotify and
   Chrome (macOS asks on first use) and Chrome's View → Developer → Allow JavaScript from Apple Events.
   Safari and other apps are out of scope.
8. **Apple Intelligence cleans up by default, Qwen is the backup (2026-10-21, user-approved).** Cleanup runs on
   Apple's on-device Foundation Models (`AppleIntelligenceCleaner`, macOS 26): built in, no download, nothing leaves
   the Mac. Whisper still transcribes. Settings → Cleanup model lists "Apple Intelligence: built in, no download"
   (the new default) plus both Qwen3 models. If Apple Intelligence is selected but unavailable (turned off in System
   Settings, still getting ready, or an ineligible Mac), Flow uses Qwen3 1.7B via MLX automatically, downloading it if
   needed, and Settings says why. `CleanupEngine.resolve` makes that choice; `AppModel.refreshCleanupEngine()` re-checks
   at launch, on every recording start and whenever Settings is opened or changed, so turning Apple Intelligence on or
   off takes effect without a restart.
   - Prompt: the same `CleanupPrompt.system`, with the worked examples as earlier prompt → response turns, plus
     three Apple-only examples (a question, a request, a filler-heavy self-correction) that stop it answering
     questions. Greedy sampling, same token cap as Qwen, guardrails set to `permissiveContentTransformations`
     (meant for rewriting the user's own text). Every clean gets a fresh session (no carry-over between
     dictations); the next one is prewarmed after each clean, which halves latency.
   - Errors (unavailable, guardrail, context window, timeout) throw, and the validator still checks the output, so
     failures paste the raw transcript as in §6.
   - Known weakness: after a bare "no" ("Tuesday no Wednesday") it can keep the first word; "no wait" works. Qwen
     misses other corrections, so this isn't a regression.
   - Migration: a saved Qwen3 1.7B (the old default) moves to Apple Intelligence once. A deliberate Qwen3 4B is
     kept, and choosing Qwen again afterwards sticks.
9. **Overlay: "Meniscus" floating glass pill (2026-10-21, user-approved).** Replaces the notch Midnight Capsule
   (item 3). Chosen from five browser mockups (`design/overlay-options/`, served with `python3 -m http.server`)
   and shrunk to 85%. A Liquid Glass capsule (`.glassEffect(.regular, in: .capsule)`) floats bottom-centre,
   **16 pt above the Dock** (the screen's `visibleFrame`), on the **screen under the mouse** (else the key
   window's screen), re-picked each time it appears. It is no longer tied to the built-in display.
   - Size: **36 pt** tall, full capsule radius, **14.5 pt** side padding, **7.5 pt** gap, **11 pt medium** type.
     Width follows the content per state (e.g. listening ≈ 114 pt, pasted ≈ 88 pt, "Microphone access needed"
     ≈ 197 pt), animated with a spring. Long messages truncate inside a 420 pt panel.
   - Content is monochrome (primary/secondary ink): **11 bars**, 2.5 pt wide with 2.5 pt gaps, 2.5–17 pt tall
     (same Calm Scroll sampling and smoothing as item 4), plus the timer. Outcomes add one 15 pt icon in a system
     colour (pasted green tick drawn on, cancelled grey ✕, no speech amber mic-slash, copied cyan clipboard, error
     red triangle) and a faint wash of that colour inside the glass. A bright lens rim catches the top-left and
     bottom-right edges. While thinking, a band of light sweeps through the glass and the "Thinking…" label.
   - Motion: rises 15 pt from below at 86% scale with a little overshoot; sinks back the same way in 0.3 s.
     Reduce Motion: fades only, no rise, sweep or tick drawing.
   - States, copy and auto-hide timings are unchanged (`PillState`). Values live in `Theme.Pill`.
10. **Speed without losing accuracy (2026-10-21, user-approved: keep Whisper large-v3 Turbo, accuracy first).**
    Measured on the M4 Pro with `LatencyBenchmarkTests` and `IncrementalAccuracyTests` (`make test-models`).
    - **Models stay loaded: keep-warm defaults to Always** (~600 MB resident; 1.6 GB with Qwen). A saved shorter time
      moves to Always once (`keepWarmMigratedToAlways`); choosing a shorter one afterwards sticks. This replaces the
      10-minute default in §2 and §5.
    - **Warm, not just loaded.** `ModelBackend.warm()` runs after launch, after a model switch, when the Mac wakes and
      when a recording starts (overlapping the speech). Whisper transcribes a moment of silence if it hasn't run for
      60 s (the first run after 5 idle minutes was +150 ms). Apple Intelligence re-prewarms its waiting session: after
      5 idle minutes a clean took 1.65 s instead of ~0.4 s.
    - **Transcribe while speaking** (Settings → "Transcribe while you speak", on by default). `ChunkPlanner` cuts the
      audio in the middle of pauses (≥ 0.5 s after ≥ 6 s of speech; ≥ 0.25 s after 20 s; at the quietest 50 ms after
      27 s, so a piece always fits one Whisper window). `IncrementalTranscription` transcribes the pieces one at a
      time in the background, each with the text so far as Whisper's previous-text prompt, and joins them with
      spaces. On release only the audio after the last finished piece is transcribed, without a prompt (each prompt
      token costs a decoder step); if that's only silence, or under 0.2 s of sound (the hotkey's click), it's
      skipped. Pieces still queued merge into that tail. Cancelling the recording cancels the pieces. Any failure
      falls back to the whole clip. Accuracy gate: 7 dictations of 8–39 s with pauses mid-sentence, 453 words:
      word error rate 2.4% incremental vs 2.4% whole clip. Release-to-text: 31–39 s dictations 1.9–2.0 s → 0.7–1.3 s;
      under 30 s about the same (~0.7–1.3 s), because Whisper's ~0.57 s encoder cost is per run, whatever its length.
    - **Long clips no longer lose words.** Whole-clip transcription used to cut at exactly 30 s, and Whisper dropped
      the sentence running into the cut (a 35 s dictation lost 70 of 91 words; WER 20.5% over the set). Clips longer
      than one window are now split at the longest pause (`chunkingStrategy: .vad`).
    - **Leading and trailing silence is trimmed** before transcribing (`SilenceDetector.speechRange`, keeping 0.3 s
      before and 0.5 s after the speech). Clips of 1 s or less are padded with silence to 2 s: WhisperKit never
      decodes the last second of a clip, so a quick "yes" used to come back empty.
    - **"Pasted" shows as soon as ⌘V is sent**, and media resumes then. The previous clipboard is still restored
      400 ms later, in the background; a paste that starts before that restore takes over the saved clipboard.
    - Whisper calls run one at a time (`WhisperKitTranscriber` queue); unloading waits for a transcription in progress.
