# Hush

A quiet menu bar app for your Mac that records your meetings, turns them into a transcript **on your Mac**, and, only if you choose, asks Claude or ChatGPT to write meeting notes.

Built by wswebcreation. The app is in Dutch.

- **Private by default.** Audio never leaves your Mac. Transcription runs on device.
- **Explicit.** Nothing is sent to Anthropic or OpenAI unless you press "Stuur naar Claude" or "Stuur naar ChatGPT" for that recording.
- **Safe.** If something fails, your audio and transcript stay on disk. Nothing is deleted unless you choose it.
- Only you can see it. Other meeting participants are not notified and see nothing.

## Requirements

- A Mac with **macOS 26 or later**
- Microphone and system audio permission (Hush asks on first launch)
- Optional, for notes: an API key from Anthropic (Claude) and/or OpenAI (ChatGPT). See [Getting an API key](#getting-an-api-key)

## Install

1. Download `Hush-<version>.zip` and unzip it (double-click). Drag **Hush** to **Applications**.
2. **First open only:** Hush is not distributed through Apple's notarization, so macOS blocks it the first time.
   - Double-click Hush. When macOS says it cannot be opened, click **Done**.
   - Open **System Settings › Privacy & Security**, scroll down to the message about Hush and click **Open Anyway**. Confirm with your password.
   - Open Hush again and click **Open**.

   Alternative in Terminal: `xattr -dr com.apple.quarantine /Applications/Hush.app`
3. A waveform icon appears in the menu bar (there is no Dock icon unless you turn it on in Instellingen › Algemeen).
4. Follow the first-launch steps: allow the microphone, then system audio.

You only do step 2 once. After an update from the same sender you may need to allow the microphone and system audio again (see Troubleshooting).

## Using Hush

1. **Start** a recording from the menu bar icon or with **⌥⌘R** (changeable in Instellingen).
2. **Stop** when the conversation is over. Hush transcribes it straight away, on your Mac. Use "Op de achtergrond" to keep working; you get a notification when it is done.
3. **Check** the transcript. "Jij" is your microphone, "Anderen" is everything your Mac plays.
4. **Choose notes**: Claude, ChatGPT, or Overslaan. Add participant names if you like.
5. **Finish.** By default the audio is deleted afterwards (it goes to the Trash); the transcript and notes stay. You can change this in Instellingen › Opslag.

Everything is saved in `~/Documents/Hush/<date time>/` (`transcript.txt`, `notities.md`, `meta.json`, and `audio.m4a` while the audio is kept). Open **Opnamen** from the menu to search and replay recordings.

## Getting an API key

Notes need an API key. A Claude Pro or ChatGPT Plus subscription does **not** include API access; API credit is separate and pay per use. Only the transcript text is sent, and an hour of conversation typically costs a few cents.

In Hush, open Instellingen › Notities and click **Hoe krijg ik een sleutel?** for a step-by-step guide, or:

| Provider | Create a key at |
| --- | --- |
| Claude | https://console.anthropic.com/settings/keys |
| ChatGPT / OpenAI | https://platform.openai.com/api-keys |

Copy the key, then click **Plak uit klembord** in the guide. Hush checks it, tests it, stores it in your Keychain and clears the clipboard. Keys are never shown again, written to disk or logged.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "Taalbestanden voor Nederlands ontbreken" | Instellingen › Transcriptie › **Download** |
| "Al 1 min geen geluid van Anderen" | System audio permission is off or nothing is playing. Check System Settings › Privacy & Security › Screen & System Audio Recording |
| Microphone not recording | System Settings › Privacy & Security › Microphone, or pick another device in Instellingen › Opname |
| Hush closed unexpectedly during a meeting | Your audio is kept. Open Opnamen and choose **Transcribeer nu** |
| Permissions asked again after an update | The build was only ad-hoc signed. Ask the sender for a build signed with a Developer ID (see below) |

---

# For developers

## Project layout

```
Sources/HushCore   UI-free logic: formatting, transcript, storage, notes providers, settings (unit tested)
Sources/Hush       AppKit + SwiftUI app, audio capture, transcription
Resources          Info.plist, entitlements, AppIcon.icns
scripts            bundle.sh (build .app), package.sh (zip for sharing), release.sh (optional notarized DMG), make-icon.swift
Tests              HushCore unit tests (Swift Testing)
handover           Original design and build specs
```

Requirements: Xcode 27 (Swift 6.4), macOS 26+ deployment target. No third party dependencies.

## Build and test

```sh
swift test                         # unit tests
scripts/bundle.sh debug            # build/Hush.app, ad-hoc signed
open build/Hush.app
scripts/bundle.sh release          # optimized build
```

Regenerate the app icon with `swift scripts/make-icon.swift`.

## Sharing Hush with colleagues (zip)

```sh
scripts/package.sh
```

This builds a release version and writes `build/Hush-<version>.zip` (made with `ditto`, which keeps the signature intact). Send that zip. Colleagues need macOS 26 or later and follow the [Install](#install) steps, including **Open Anyway** on first launch.

### Keep permissions stable across updates

macOS remembers microphone and audio-capture permission per app *signature*. An ad-hoc signature (the default) changes with every build, so everyone is asked again after each update. To avoid that, sign with a **Developer ID Application** certificate (Apple Developer Program). You do not need to notarize for this.

1. Find your identity:
   ```sh
   security find-identity -v -p codesigning
   ```
   It looks like `Developer ID Application: Your Name (TEAMID)`.
2. Build with it:
   ```sh
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package.sh
   ```

Keep the bundle id (`nl.techchamps.hush`) and the signing identity the same between releases. Colleagues still do **Open Anyway** once, because the app is not notarized.

### What the signing needs

- Hardened Runtime (`--options runtime`, set by `bundle.sh`)
- Entitlement `com.apple.security.device.audio-input` (`Resources/Hush.entitlements`)
- Info.plist keys `NSMicrophoneUsageDescription`, `NSAudioCaptureUsageDescription`, `NSSpeechRecognitionUsageDescription`, `LSUIElement`
- No App Sandbox in v1

### Optional: notarized DMG (no warnings at all)

If you later want colleagues (or others) to open Hush with no warning, notarize it. This sends the app to Apple for an automated malware scan.

1. Create an app-specific password at https://account.apple.com (Sign-In and Security) and store credentials once:
   ```sh
   xcrun notarytool store-credentials "hush-notary" \
     --apple-id "you@example.com" --team-id "TEAMID" --password "<app-specific-password>"
   ```
2. Run:
   ```sh
   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
   export NOTARY_PROFILE="hush-notary"
   scripts/release.sh
   ```
   This signs, notarizes, staples the ticket and writes `build/Hush-<version>.dmg`.

| Problem | Fix |
| --- | --- |
| `The specified item could not be found in the keychain` | `SIGN_IDENTITY` does not match the `security find-identity` output |
| `notarytool` reports "Invalid" | `xcrun notarytool log <submission-id> --keychain-profile hush-notary` shows the reason |

## Design notes and deviations from the spec

- Recorder and transcriber run in the app process, not as XPC services (SwiftPM cannot build XPC bundles; that needs an Xcode project).
- Audio is written to `mic.caf` and `system.caf` (crash safe); `audio.m4a` is mixed after stopping.
- Transcription uses `SpeechTranscriber` when the language is supported and falls back to `DictationTranscriber` otherwise (Dutch uses the fallback on current macOS).
- Strings live in `HushCore/L10n.swift`, not a String Catalog. Dutch is the only language.
- No in-app updater, so there is no "Zoek naar updates" button.
- System audio permission has no public preflight API; "Toegestaan" means an audio tap was created successfully.
- Added a transcription language picker (Nederlands / English) in Instellingen › Transcriptie.
