# Settings window decision (Task 20)

Chosen on 2026-10-16 from https://claude.ai/artifact/87MC9rY51aDrsvazKjufLG:
**Layout A, a single grouped form** (the "Component: settings window" board), as in the plan's Task 21 code.
Source of the mockup: `docs/mockups/settings-canvas/project/Settings.dc.html`.

Sections, in order (`Form` with `.formStyle(.grouped)`, about 540 pt wide; follows the system light/dark appearance):

1. **Shortcut**
   - Row "Dictate", subtitle "Tap to start and stop · hold to talk · Esc cancels".
   - On the right, the recorder button (shows `⌥→`, or "Press a key or shortcut…" while recording), then **Reset** (disabled when already at the default).
   - Under the row, an inline message: orange for a clash warning ("⌘Space is normally used for Spotlight."), red for a rejection.
2. **Microphone:** row "Input", picker with "System default" plus each input device.
3. **Models:**
   - "Speech recognition" picker, with a status line under the label: "Ready ✓" in green, or "Downloading… NN%".
   - "Cleanup model" picker, with the same status line.
   - "Clean up text" toggle, subtitle "Removes ums and repeats, fixes punctuation. Off pastes the raw transcript."
   - "Keep models loaded for" picker, subtitle "Longer = instant dictation; shorter frees about 2 GB of memory sooner."
4. **Permissions:**
   - "Microphone": "✓ Allowed" in green, or an **Open Settings** button.
   - "Accessibility", subtitle "Lets Flow see the shortcut in any app and paste for you.": "✓ Allowed", or **Open Settings**.

Copy for a rejected lone modifier: "That key can’t be used on its own. Try Right ⌥, Right ⌘ or a combo like ⌥→."
