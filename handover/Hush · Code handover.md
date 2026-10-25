# Hush · Code handover

Oct 25, 2026 · @Wim Selles

## Scope of v1

Hush v1 is a native Swift menu bar app for macOS 27 that records mic plus system audio, transcribes fully on device, and optionally sends the transcript to Claude or ChatGPT for notes. Single user, distributed outside the App Store with Developer ID. Screens and flows are specified in the design handover.

**In scope**

- Manual start and stop from the menu bar or a global shortcut.
- Two channels: **You** (mic) and **Them** (system output, headphones or speakers alike).
- On device transcription with Apple's Speech framework; works offline.
- Local storage per recording, named by date and time range.
- Post recording flow: review transcript, pick Claude, ChatGPT or skip, add participant names, delete audio (default yes).
- Fail safes: nothing deleted after an error; recorder isolated so a crash loses at most a few seconds and never affects the Mac.

**Not in v1**

- Diarization of individual remote speakers.
- Auto detection of meeting apps.
- Local LLM for notes.
- App Store distribution or sandboxing beyond what Developer ID needs.

## Architecture

Hush is one app bundle with two embedded XPC services. Recording and transcription run in their own processes, so a crash there never takes down the UI, and launchd restarts the service on the next request.

&#91;embedded content: process architecture · app plus 2 XPC services\]

Audio and transcripts stay in the recordings folder; only transcript text goes to a cloud model, and only after an explicit choice.

- **Hush.app** owns the UI, the session state machine, and the notes client. It never touches audio buffers.
- **HushRecorder.xpc** captures both channels and writes them to disk. Keeping it separate means a Core Audio crash or hang is contained and the files written so far are intact.
- **HushTranscriber.xpc** reads the audio files and produces the transcript. Memory heavy work is isolated and released when it finishes.

A note on "crashing the whole Mac": a normal user space app cannot crash macOS. The real risks are a stuck audio device or a lost recording, and process isolation plus chunked writes cover both. Hush installs no kernel extension or audio driver.

## Tech stack and requirements

Everything is first party Apple frameworks plus two HTTPS APIs; there are no third party dependencies in v1 and no recurring costs beyond your own API usage.

| Area | Choice | Notes |
| --- | --- | --- |
| Language | Swift 6, strict concurrency | Actors for the session coordinator and services |
| UI | SwiftUI, `MenuBarExtra`, AppKit where needed | `LSUIElement = YES` so no Dock icon by default |
| Mic capture | `AVAudioEngine` input node | Uses the selected input device |
| System audio | Core Audio process tap (`CATapDescription`, `AudioHardwareCreateProcessTap`) in a private aggregate device | No virtual driver like BlackHole needed |
| Transcription | `Speech` framework: `SpeechAnalyzer` + `SpeechTranscriber` | On device, Dutch and English assets managed by the system |
| IPC | `NSXPCConnection` to bundled XPC services | Typed protocols, codable messages |
| Secrets | Keychain (`kSecClassGenericPassword`) | API keys never in UserDefaults or files |
| Networking | `URLSession` async | Anthropic Messages API, OpenAI API |
| Logging | `os.Logger` with subsystem `nl.techchamps.hush` | Never log transcript text or keys |
| Target | macOS 27 (minimum 26) | `SpeechAnalyzer` needs 26 or later |

## Audio capture

The recorder writes two separate mono files, one per channel, so "You" and "Them" stay separable for transcription without any diarization.

**Mic (You)**

- `AVAudioEngine.inputNode` with a tap; downmix to mono, resample to 16 kHz.
- Info.plist: `NSMicrophoneUsageDescription`.

**System output (Them)**

- Create a `CATapDescription` with `monoGlobalTapButExcludeProcesses:` and exclude Hush's own processes to avoid feedback. Not muted, so you still hear the meeting.
- Pass it to `AudioHardwareCreateProcessTap`, add the tap to a private aggregate device, and read buffers from the aggregate device's IO proc. Apple documents this in [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
- Info.plist: `NSAudioCaptureUsageDescription`. The tap follows the default output device, so headphones and built in speakers both work.
- **Gotcha:** if the user denies permission, the Core Audio calls still return `noErr` and simply deliver silence ([write up](https://dev.to/nickdelv/2000-buffers-of-nothing-3i8)). Detect this with a level check: if the tap delivers pure digital zero for 10 s while the system is playing audio, show the "System audio access is off" state.

**File format and crash safety**

- Write CAF (`AVAudioFile`, 16 kHz, 16 bit PCM mono). CAF stays readable after an abrupt stop, unlike WAV whose header is written at the end.
- Roll a new chunk file every 5 minutes (`mic-0001.caf`, `system-0001.caf`, …) and flush every 5 seconds. A crash loses at most 5 seconds.
- Write `session.json` at start (state `recording`, start time, devices) and update it on stop. On launch, any session still marked `recording` is recovered: chunks are kept and the user is offered transcription.
- React to device changes (headphones plugged in, AirPods connected) via `kAudioHardwarePropertyDefaultOutputDevice` listeners and rebuild the aggregate device without stopping the session.

## On device transcription

Transcription uses Apple's `SpeechAnalyzer` with the `SpeechTranscriber` module, which runs entirely on device with a system managed model and is built for long form, distant audio such as meetings ([Apple, WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)). It is free and works offline once the language assets are installed.

- Run after the recording stops, not live. This keeps CPU near zero during the meeting and lets the analyzer work on complete files.
- Transcribe the mic and system files as two separate passes, each with time ranges per segment. Merge by timestamp into one transcript with `You` and `Them` tags.
- Language: let the user set a default (Dutch or English) in Settings, and check `SpeechTranscriber` asset availability with `AssetInventory` on first launch; offer the download in onboarding.
- If `SpeechTranscriber` does not support a locale, fall back to `DictationTranscriber`.
- Output two files: `transcript.md` (human readable) and `transcript.json` (segments with start, end, speaker, text) for later features like diarization.
- Process chunk by chunk and write progress to `session.json`, so a crashed transcription resumes at the last finished chunk instead of starting over.

Example merged output:

```markdown
[00:00:04] You: Shall we start with the release planning?
[00:00:09] Them: Yes, we moved the beta to the 3rd of November.
```

## Storage layout

Each recording gets its own folder named by date and time range, inside a user chosen root (default `~/Documents/Hush`). The folder is renamed from start time to full range when the recording stops.

```markdown
~/Documents/Hush/
  2026-10-21 1400-1445/
    session.json        state, devices, participants, provider, timestamps
    audio/
      mic-0001.caf
      system-0001.caf
    transcript.md
    transcript.json
    notes.md            only if notes were generated
```

- While recording, the folder is `2026-10-21 1400-recording`; the library hides nothing, so a crashed session is visible.
- `session.json` states: `recording`, `recorded`, `transcribing`, `transcribed`, `notes_pending`, `complete`, `failed` (with an error code and the step it failed in).
- Deleting audio removes the `audio/` folder only, via `FileManager.trashItem` (to the Trash, recoverable), and only when `transcript.md` exists and is non-empty.
- Exclude the `audio/` folder from Time Machine (`URLResourceValues.isExcludedFromBackup`) to avoid backing up large raw files; transcripts and notes stay backed up.

## Notes generation

Notes are one HTTPS call to the provider picked in the post recording flow, built from an editable prompt template plus the transcript. Note that API keys are billed per use and separately from Claude Pro or ChatGPT Plus subscriptions.

| Provider | Endpoint | Auth | Model |
| --- | --- | --- | --- |
| Claude | `POST https://api.anthropic.com/v1/messages` | `x-api-key` header + `anthropic-version` | Picker in Settings, for example `claude-sonnet-5-5` |
| ChatGPT | OpenAI API (Responses or Chat Completions) | `Authorization: Bearer` | Picker in Settings, free text model id |

- Define a `NotesProvider` protocol (`func generateNotes(prompt: String) async throws -> String`) with one implementation per provider, so adding a local model later is one new type.
- Timeout 120 s, one automatic retry on 429 or 5xx with backoff, then show the failure state.
- Keys live in the Keychain; the **Test** button in Settings sends a tiny request and shows OK or the error.
- The request contains transcript text only, never audio, file paths or device names.

**Default prompt template** (editable in Settings; placeholders are filled by the app):

```markdown
You are writing private meeting notes for {{me}}.
The transcript below has two speaker tags: "You" is {{me}}, "Them" is
everyone else in the call. Other participants: {{participants}}.
Meeting date and time: {{date}}, {{time_range}}.

Write the notes with these sections:
1. Summary: one short paragraph.
2. Key points discussed.
3. Decisions made.
4. Action points as a checklist, split into "Mine" (written in first
   person) and "Others". Include owner and deadline when mentioned.
5. Open questions and follow ups.

Only use what is in the transcript. If something is unclear, say so
instead of guessing. Output markdown only.

Transcript:
{{transcript}}
```

## Performance budget

The budget below is a target to test against with Instruments, not a measured result. The main lever is doing nothing heavy while recording: capture and write only, transcribe afterwards.

| State | CPU (Apple silicon) | Memory | Energy impact |
| --- | --- | --- | --- |
| Idle in menu bar | \~0% | < 40 MB | Low, no timers or polling |
| Recording (2 channels) | < 3% | < 80 MB | Low, comparable to a voice memo |
| Transcribing a 1 h meeting | Bursty, allowed to be high | < 1 GB, released afterwards | Runs at `.utility` QoS; pause on low power mode when on battery |
| Notes request | Negligible | Negligible | One network call |

Rules that keep it there:

- No live transcription, waveform rendering or level meters when the menu is closed. Meters update at 10 Hz only while the dropdown is open.
- Audio buffers are written straight to disk; nothing is held in memory beyond a small ring buffer.
- 16 kHz mono PCM is about 115 MB per channel per hour; with audio deletion on by default the folder stays small.
- Transcription runs in the XPC service, which exits when done, so its memory is returned to the system.
- When on battery below 20%, ask before transcribing: "Transcribe now or when plugged in?"

## Fail safes and error handling

The single rule: data is only ever removed after the next step's output is verified on disk, and only by explicit user choice.

| Step | What can fail | What Hush does | Data kept |
| --- | --- | --- | --- |
| Start | Missing permission, no input device | Refuse to start, show the reason and a fix button | n/a |
| Recording | Recorder XPC crashes | App detects the invalidated connection, marks session `failed: recorder_crashed`, offers to restart capture into a new chunk | All chunks so far |
| Recording | Device switch, tap silent | Rebuild aggregate device; warn after 60 s of silence | All chunks |
| Recording | Disk full | Stop cleanly, finalize current chunk, notify | All chunks |
| Stop | App or Mac crashes before stop | On next launch, recover any `recording` session | All chunks |
| Transcription | Asset missing, analyzer error, XPC crash | Mark `failed: transcription`, resume from last finished chunk on retry | Audio, partial transcript |
| Notes | No key, timeout, 4xx/5xx | Show error with Retry, other provider, Skip | Audio, transcript |
| Delete audio | Transcript missing or empty | Delete button disabled; checkbox forced off | Audio |

Implementation notes:

- Every state change is written to `session.json` atomically (`Data.write(options: .atomic)`) before acting on it.
- XPC services set `NSXPCConnection.invalidationHandler` and `interruptionHandler`; the coordinator treats both as a failure of that step, never as "done".
- Deletion goes to the Trash, not `removeItem`, so even a wrong delete is recoverable.
- Unit test each row of this table with a fake recorder and fake provider before UI work.

## Signing and distribution

Hush ships outside the App Store with your existing Apple Developer Program membership: sign with a Developer ID Application certificate and notarize, so Gatekeeper opens it without warnings.

1. Bundle id `nl.techchamps.hush`; XPC services `nl.techchamps.hush.recorder` and `nl.techchamps.hush.transcriber`.
2. Enable Hardened Runtime. Entitlement `com.apple.security.device.audio-input` for the mic. No App Sandbox in v1 (simpler file access to the chosen folder); it can be added later.
3. Info.plist keys: `NSMicrophoneUsageDescription`, `NSAudioCaptureUsageDescription`, `LSUIElement`.
4. Archive in Xcode, export with Developer ID, then `xcrun notarytool submit --wait` and `xcrun stapler staple`.
5. Distribute as a DMG or zip. Launch at login via `SMAppService.mainApp`.

Keep the TCC permissions stable by never changing the bundle id or signing identity between builds; otherwise macOS asks for mic and audio capture access again.

## Build order and skills

Build the risky parts first: system audio capture, then transcription, then UI. Each milestone ends with something you can run.

1. **Spike: capture.** CLI target that records mic + system tap to two CAF files for 60 s. Proves permissions, tap, device switching.
2. **Recorder XPC + session journal.** Move capture into the service, add chunking, `session.json`, crash recovery. Kill the service mid recording and verify the files.
3. **Transcriber XPC.** `SpeechAnalyzer` over the chunks, merge You and Them, write `transcript.md` and `.json`. Test with a Dutch and an English meeting.
4. **Menu bar app.** Idle and recording states, shortcut, level meters.
5. **Post recording flow.** Steps 1 to 5 with both failure paths.
6. **Notes providers.** Claude and OpenAI clients, Keychain, prompt template, Test buttons.
7. **Library and settings.** Then performance pass in Instruments against the budget.
8. **Sign, notarize, install.** Use it in real meetings for a week before adding anything.

**Suggested Claude Code skills** (one `SKILL.md` each, loaded when working on that part):

| Skill | Covers |
| --- | --- |
| `hush-project-brief` | Scope, architecture, storage layout, fail safe rule; always loaded |
| `hush-audio-capture` | AVAudioEngine mic, Core Audio tap + aggregate device, CAF chunking, the silent tap gotcha |
| `hush-transcription` | SpeechAnalyzer setup, assets, merge format, resume logic |
| `hush-notes-providers` | Provider protocol, both APIs, Keychain, prompt template, retries |
| `hush-ui-design` | Tokens, screens and states from the design handover, no Liquid Glass |
| `hush-release` | Entitlements, Info.plist keys, notarytool steps |
|  |  |

Draft these six skills before starting milestone 1, and keep them in the repo under \`.claude/skills/\`.
