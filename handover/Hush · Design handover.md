# Hush · Design handover

Oct 25, 2026 · @Wim Selles

## What Hush is

Hush is a small macOS menu bar app that records your microphone and your Mac's audio output, transcribes it on device, and optionally turns it into meeting notes. It is a private memory aid for one person: you. Nothing is shown to other meeting participants, and the audio never leaves the Mac.

Design principles:

- **Quiet.** It lives in the menu bar, takes no Dock space by default, and only asks for attention when a recording ends.
- **Plain and dark.** Dark mode first, flat surfaces, no decoration. It should feel like a tool, not a product launch.
- **Explicit at every step.** Nothing is sent to a cloud model or deleted without the user choosing it in that moment.
- **Safe by default.** If anything fails, the audio and transcript stay on disk and the UI says so plainly.

## Visual direction

Hush is dark mode first and uses no Liquid Glass: solid, opaque surfaces only, no translucency, no blur, no glossy highlights. Light mode may follow later but is not designed for v1.

| Token | Value | Use |
| --- | --- | --- |
| Background | #111214 | Window background |
| Surface | #1A1B1E | Panels, list rows, dialog body |
| Surface raised | #232428 | Hovered rows, input fields |
| Border | #2E3035 | 1 px dividers and field outlines |
| Text primary | #E8E9EB | Body text, titles |
| Text secondary | #9A9DA3 | Labels, timestamps, hints |
| Accent | #5B8DEF | Primary buttons, selection, focus ring |
| Recording | #E5484D | Recording dot and timer only |
| Success | #3FB950 | Completed step check |
| Warning | #D29922 | Recoverable errors, "audio kept" notices |

These values are a starting proposal; adjust freely as long as contrast stays at WCAG AA or better.

- **Type:** SF Pro (system font). Window titles 15 pt semibold, body 13 pt, secondary 11 pt. Transcript text in SF Mono 12 pt for easy scanning.
- **Shape:** 8 px corner radius on panels and buttons, 6 px on fields. No shadows except the system window shadow.
- **Spacing:** 8 px grid, 16 px window padding, 12 px between form rows.
- **Icons:** SF Symbols, monochrome, regular weight. The menu bar icon is a simple template glyph (for example `waveform` or a custom closed-mouth glyph) that turns into a filled red dot while recording.
- **Motion:** minimal. A gentle pulse on the recording dot, a progress bar during transcription, nothing else.

## Screen inventory

Version 1 has five surfaces. Everything starts from the menu bar; the app can also be opened from Launchpad or Spotlight, which opens the Recordings window.

| # | Surface | Type | Opens from |
| --- | --- | --- | --- |
| 1 | Menu bar dropdown (idle) | NSMenu or small popover, \~280 px wide | Menu bar icon |
| 2 | Menu bar dropdown (recording) | Same popover, recording state | Menu bar icon while recording |
| 3 | Post recording flow | Single window, 560 × 520 px, stepped | Stopping a recording |
| 4 | Recordings library | Resizable window, min 800 × 500 px | Menu, app launch, notes link |
| 5 | Settings | Standard settings window with tabs | Menu, Cmd+, |

## Menu bar dropdown

The menu bar is the main control surface: one click to start, one click to stop.

**Idle state**

1. Primary button: **Start recording** (accent colour, full width). Shortcut hint on the right, for example ⌥⌘R.
2. Source status line in secondary text: "Mic: MacBook Pro Microphone · Output: system audio". Shows a warning icon if a permission is missing, which links to Settings.
3. Divider.
4. **Recent recordings**: the last 3, each as "Tue 21 Oct · 14:00 to 14:45" with a small badge (Transcript, Notes, or Failed).
5. **Open recordings…**, **Settings…**, **Quit Hush**.

**Recording state**

1. Red pulsing dot plus elapsed timer in large monospaced digits, for example 00:23:41.
2. Two live level meters: "You" (mic) and "Them" (system output), thin horizontal bars. These reassure the user that both sides are captured.
3. Primary button: **Stop recording** (red outline, full width).
4. Secondary: **Pause** / **Resume**.
5. The menu bar icon itself shows the red dot so the state is visible without opening the menu.

If one source goes silent for more than 60 seconds (for example headphones unplugged), show a small inline warning under the meters: "No audio from Them for 1 min".

## Post recording flow

Stopping a recording opens one window that walks through five steps. A step indicator at the top (five dots or a slim segmented bar) shows where the user is. Back is allowed until notes are sent.

&#91;embedded content: post recording flow · 5 steps, 2 failure paths\]

Skipping notes goes straight to Finish; a failure never deletes anything.

1. **Transcribing.** Opens automatically. Shows the recording's title ("Tue 21 Oct · 14:00 to 14:45"), a determinate progress bar, and the line "Transcribing on this Mac. Nothing is uploaded." Buttons: Cancel (keeps audio) and Run in background (closes the window, notifies when done).
2. **Review transcript.** Scrollable transcript in monospace, each line prefixed with a timestamp and a speaker tag (**You** in accent colour, **Them** in secondary). Read only in v1, with Copy and Reveal in Finder buttons. Continue moves on.
3. **Notes.** Title: "Generate notes from this transcript?" A three-option segmented control: **Claude**, **ChatGPT**, **Skip**. Below it, a participants field: "Who else was in this call?" as a token field (type a name, press Enter). A small notice under the field: "The transcript will be sent to Anthropic" or "to OpenAI", changing with the choice. Primary button reads **Send to Claude**, **Send to ChatGPT**, or **Continue without notes**.
4. **Generating notes.** Spinner plus "Waiting for Claude…". When done, show the notes rendered as markdown with Copy and Open buttons.
5. **Finish.** Summary of what was saved (transcript, notes, audio) with the folder path. A checkbox, ticked by default: **Delete the audio recording**. Primary button **Done**; secondary **Open in Recordings**.

## Recordings library

A two pane window: a list of recordings on the left, the selected recording on the right.

**Left pane (sidebar, \~260 px)**

- Search field at the top (searches titles and transcript text).
- Recordings grouped by day (Today, Yesterday, then dates), newest first.
- Each row: time range "14:00 to 14:45", duration in secondary text, and status icons for transcript, notes and audio (present or deleted). A failed recording shows a warning icon.

**Right pane (detail)**

- Header: date and time range, participants (if entered), buttons **Generate notes** (re-opens step 3 of the flow), **Reveal in Finder**, and a **…** menu with Delete recording.
- Tabs: **Notes** (rendered markdown, default if present) and **Transcript** (monospace, You and Them tagged).
- If the audio was kept: a slim audio player bar at the bottom.
- For a failed recording: a warning banner with **Retry transcription**.

**Empty state:** a centred glyph, "No recordings yet", and the hint "Start one from the menu bar or press ⌥⌘R."

## Settings

A standard settings window with a tab bar at the top. Each tab is a simple form: label on the left, control on the right.

| Tab | Controls |
| --- | --- |
| General | Your name (used as "You" in prompts, default Wim) · Launch at login toggle · Show Dock icon toggle · Global shortcut recorder (default ⌥⌘R) |
| Recording | Microphone picker (System default plus devices) · Capture system audio toggle (on) · Permission status rows for Microphone and System audio, each with a green check or a **Grant access** button |
| Storage | Recordings folder with **Choose…** and **Reveal** (default \~/Documents/Hush) · Default for "Delete audio after finishing" (on) |
| Transcription | Engine: Apple on device (only option in v1, shown read only) · Language model status: "Dutch and English assets installed" with **Download** if missing |
| Notes | Claude API key (secure field, **Test** button) · Claude model picker · OpenAI API key (secure field, **Test**) · OpenAI model picker · Prompt template: multi-line editor with **Reset to default** |

API key fields never show the key after saving; they display "Saved in Keychain" with a Replace button.

## Error, empty and edge states

Every error tells the user what is safe and what to do next, in one line each. Warnings use the amber colour, never red (red means recording).

| Situation | Where it shows | Message and actions |
| --- | --- | --- |
| First launch, no permissions | Onboarding sheet, 2 steps | Explain mic and system audio access, **Grant** buttons, then a test meter for each |
| Permission revoked later | Menu bar dropdown, Settings | "System audio access is off. Only your mic will be recorded." · **Open Settings** |
| Disk nearly full (< 2 GB) | Menu bar before starting | "Low disk space. Recording may stop early." · Start anyway |
| Recorder crashed mid meeting | Notification + library banner on next open | "Hush stopped unexpectedly. 32 min of audio was saved." · **Transcribe now** |
| Transcription failed | Flow step 1, library | "Transcription failed. Your audio is safe." · **Retry**, **Close** |
| No API key for chosen model | Flow step 3 | Send button disabled, inline link "Add a Claude key in Settings" |
| Notes request failed or timed out | Flow step 4 | "Couldn't reach Claude. Your transcript is saved." · **Retry**, **Try ChatGPT**, **Skip** |
| Very short recording (< 10 s) | On stop | "Recording too short to keep." · **Keep anyway**, **Discard** |
| App quit while recording | Quit confirmation | "A recording is in progress." · **Stop and save**, **Cancel** |

## Out of scope for v1

- Speaker diarization (Speaker 1, 2, 3) and naming individual voices.
- Automatic detection of Teams, Zoom or Meet calls.
- Local LLM option for notes.
- Editing the transcript in place.
- Light mode.

## Prompt for Claude Design

Copy this into Claude Design together with this document:

```markdown
Design the macOS app "Hush" as described in the attached design handover.
Make five screens: menu bar dropdown (idle), menu bar dropdown (recording),
the post recording window (one frame per step, 1 to 5, plus the two failure
states), the recordings library (with content and empty state), and settings
(Notes tab shown). Dark mode only. Solid opaque surfaces, no translucency,
no blur, no Liquid Glass. Use the colour tokens, SF Pro type scale, 8 px grid
and 8 px radius from the handover. Native macOS proportions, not iOS.
```
