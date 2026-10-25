# Hush · Build handover for Claude Code

Version 1 · 25 Oct 2026 · Wim Selles

This document is the complete spec for building **Hush v1**, a native macOS menu bar app. It replaces the earlier design handover and includes everything from the approved design canvas: tokens, every screen, every Dutch string, behaviour, states and edge cases. Where this document and your own assumptions differ, follow this document. Where something is not specified, choose the most native macOS behaviour and note the choice in the PR description.

**The whole app UI is in Dutch.** All user-facing strings are listed in section 9 and must be used exactly as written.

**Visual reference:** every screen and key state is in `docs/design/` as a PNG at 2x (see section 4.1). Look at the matching image before building a screen and compare your result against it. **This text spec is leading:** if an image and this document differ on a value (size, colour, copy, behaviour), follow this document. The images were rendered with Inter and DejaVu Sans Mono as stand-ins, so the real app with SF Pro and SF Mono will look slightly different in letter shapes and widths.

---

## 1. What Hush is

Hush records your microphone and your Mac's audio output, transcribes it on device, and optionally turns the transcript into meeting notes with Claude or ChatGPT. It is a private memory aid for one person. Nothing is shown to other meeting participants and the audio never leaves the Mac.

Principles that drive every decision:

1. **Quiet.** Lives in the menu bar, no Dock icon by default, only asks for attention when a recording ends.
2. **Plain and dark.** Dark mode only, flat opaque surfaces, no decoration.
3. **Explicit at every step.** Nothing is sent to a cloud model and nothing is deleted unless the user chooses it in that moment.
4. **Safe by default.** If anything fails, audio and transcript stay on disk and the UI says so plainly.

---

## 2. Technical direction

These are recommendations. Verify each API against current Apple documentation for the deployment target before you build on it, and flag anything that does not hold.

| Area | Recommendation |
| --- | --- |
| Language and UI | Swift, SwiftUI for all views, AppKit where SwiftUI falls short (status item, panels, window chrome). |
| Deployment target | The latest macOS that offers the on-device speech APIs below. Confirm and state the minimum in the README. |
| App type | Menu bar agent (`LSUIElement = YES`). Switch to `.regular` activation policy only when "Toon symbool in het Dock" is on. |
| Menu bar | `NSStatusItem` with a custom opaque panel (NSPanel or NSPopover hosting SwiftUI) rather than a plain `NSMenu`, so the timer, level meters and buttons can be drawn exactly as designed. |
| Microphone capture | `AVAudioEngine` input node, device chosen in Settings (default: system default). |
| System audio capture | Core Audio process taps or ScreenCaptureKit audio-only capture, whichever the deployment target supports best. Capture system output only, never the screen. |
| Recording format | Two separate tracks (mic and system) so speaker tags can be derived from the source. Store a mixed `audio.m4a` for playback. |
| Transcription | Apple on-device speech recognition (SpeechAnalyzer / SpeechTranscriber if available on the target, otherwise `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`). Transcribe each track separately and merge by timestamp. Languages: Dutch and English. |
| Speaker tags | No diarization. Mic track = **Jij**, system track = **Anderen**. |
| Notes | Anthropic Messages API (Claude) and OpenAI API (ChatGPT), plain HTTPS from the app. Only the transcript text is sent. |
| Secrets | API keys in the macOS Keychain only. Never written to disk, logs or UserDefaults. |
| Global shortcut | Default ⌥⌘R, user configurable. Use a well maintained shortcut recorder package or Carbon `RegisterEventHotKey`. |
| Launch at login | `SMAppService.mainApp`. |
| Localization | String Catalog (`Localizable.xcstrings`) with **Dutch (nl) as the development and only language** in v1. No hardcoded strings in views. |
| Notifications | `UserNotifications` for "transcription done" (after Op de achtergrond) and crash recovery. |

### Visual rules that affect implementation

- **No Liquid Glass, no translucency, no blur, no vibrancy, no materials.** Every window, panel and popover gets an explicit opaque background colour from the tokens. Do not use `.glassEffect`, `.ultraThinMaterial`, `NSVisualEffectView` or the default translucent popover/menu backgrounds. If a system container insists on a material, cover it with an opaque view.
- Dark mode only. Force `NSAppearance(named: .darkAqua)` on the app.
- No custom shadows. The only shadow is the system window shadow, plus the system shadow on the menu bar panel.
- Motion: a gentle opacity pulse on the recording dot (1.6 s ease-in-out, 1.0 to 0.45) and the determinate progress bar. Respect Reduce Motion (no pulse, no spinner rotation).

---

## 3. Design tokens

Define these once (for example a `Theme` enum with `Color` and `NSColor` values) and never use raw hex in views.

### Colours

| Token | Hex | Use |
| --- | --- | --- |
| `background` | `#111214` | Window background |
| `surface` | `#1A1B1E` | Panels, sidebar, list areas, menu bar panel |
| `surfaceRaised` | `#232428` | Input fields, secondary buttons, selected settings tab |
| `border` | `#2E3035` | 1 px dividers, field and panel outlines, meter tracks |
| `textPrimary` | `#E8E9EB` | Body text, titles |
| `textSecondary` | `#9A9DA3` | Labels, timestamps, hints, "Anderen" tag |
| `textTertiary` | `#C4C7CC` | Second line inside warning banners, neutral badge text |
| `accent` | `#5B8DEF` | "Jij" tag, level meter (Jij), progress fill, links, focus ring, selected settings icon |
| `accentFill` | `#3A6BD4` | **Background of primary buttons, selected segments and selected list rows** (white text on it reaches about 5:1; white on `#5B8DEF` fails AA) |
| `recording` | `#E5484D` | Recording dot, timer, Stop opname outline. Nothing else. |
| `success` | `#3FB950` | Completed step checks, "saved" checks |
| `warning` | `#D29922` | Recoverable errors, warning icons and text. Never use red for errors. |
| `warningSurface` | `#241E12` | Warning banner background |
| `warningBorder` | `#4A3B1A` | Warning banner border |
| `badgeNotesBg` / `badgeNotesText` | `#1E2A44` / `#7FA6F3` | "Notities" badge, numbered step circles |
| `badgeNeutralBg` | `#26282C` | "Transcript" badge |
| `badgeWarningBg` | `#2A2312` | "Mislukt" badge |
| `disabledText` | `#6B6E74` | Disabled primary button text (on `surfaceRaised`) |
| `deletedIcon` | `#7A7D84` | "Audio verwijderd" icon in the library |
| `desktop` | `#0B0C0E` | Only used in mockups behind the menu bar panel |

All text pairs must meet WCAG AA (4.5:1 for 11 to 13 pt text). The values above already do.

### Typography

SF Pro (system font) and SF Mono.

| Style | Spec |
| --- | --- |
| Window / screen title | 15 pt semibold, line height 20 |
| Body | 13 pt regular, line height 18 to 20 |
| Secondary | 11 pt regular, line height 16 |
| Section label | 11 pt semibold, `textSecondary` |
| Transcript | SF Mono 12 pt, line height 18 |
| Timer | SF Mono 32 pt medium, tabular digits, `recording` colour |
| About app name | 20 pt semibold |

### Shape and spacing

- 8 px grid. Window padding 16 px (some content areas use 24 or 48 px side padding, see screens). 12 px between form rows.
- Corner radius: 8 px on panels and buttons, 6 px on fields, segments inside a segmented control and list rows, 4 px on badges and tokens, 10 px window corners (system).
- Buttons: height 28 px in windows, 32 px in the menu bar panel, horizontal padding 16 px (12 px when the button has an icon).
- Primary button: `accentFill` background, white 13 pt semibold text, no border.
- Secondary button: `surfaceRaised` background, 1 px `border`, `textPrimary` 13 pt.
- Icons: SF Symbols, monochrome, regular weight, 12 to 14 pt inline, 18 pt in the settings toolbar.

---

## 4. Screen inventory

| # | Screen | Type | Size | Opens from |
| --- | --- | --- | --- | --- |
| 1 | Menubalk · Inactief | Status item panel | 280 px wide | Menu bar icon |
| 2 | Menubalk · Opname | Same panel, recording state | 280 px wide | Menu bar icon while recording |
| 3 | Na de opname (steps 3.1 to 3.5 + 2 failure states) | One window, stepped | 560 × 520 | Stopping a recording |
| 4 | Opnamen (library), with content and empty | Resizable window | min 800 × 500, default 1100 × 700 | Menu, app launch, Open in Opnamen |
| 5 | Instellingen (Algemeen, Opname, Opslag, Transcriptie, Notities) | Settings window with toolbar tabs | 640 wide, height fits tab | Menu, ⌘, |
| 6 | Over Hush | About window | 360 × 440 | App menu "Over Hush" |
| 7 | Zo werkt Hush | Help / welcome window | 560 × 520 | First launch (after permissions), Help menu |

Screens 1 to 4, Instellingen › Algemeen, Instellingen › Notities, 6 and 7 are designed. Instellingen › Opname, Opslag and Transcriptie are **not drawn**: build them with the same form pattern as Algemeen using the controls in section 5.5.

### 4.1 Visual reference images

All files are in `docs/design/`, PNG at 2x (so a 560 × 520 window is 1120 × 1040 px). Window corners are transparent.

| Image | Shows | Section |
| --- | --- | --- |
| `01-menubalk-inactief.png` | Menu bar panel, idle, with the menu bar strip above it | 5.2 |
| `02-menubalk-opname.png` | Menu bar panel while recording | 5.3 |
| `02-menubalk-opname-stilte.png` | Recording with the silence warning (Anderen silent) | 5.3 |
| `03-1-transcriberen.png` | Step 3.1, transcribing at 62% | 5.4 |
| `03-2-controleren.png` | Step 3.2, transcript review | 5.4 |
| `03-3-notities.png` | Step 3.3, Claude selected, participants entered | 5.4 |
| `03-3-notities-overslaan.png` | Step 3.3, Overslaan selected (participants hidden) | 5.4 |
| `03-3-notities-geen-sleutel.png` | Step 3.3, no API key: warning, link and disabled button | 5.4 |
| `03-4-genereren-wachten.png` | Step 3.4, waiting for Claude | 5.4 |
| `03-4-genereren-klaar.png` | Step 3.4, notes ready | 5.4 |
| `03-5-afronden.png` | Step 3.5, saved summary and delete audio checkbox | 5.4 |
| `03-1-fout-transcriptie-mislukt.png` | Transcription failed | 5.4 |
| `03-4-fout-notities-mislukt.png` | Notes request failed | 5.4 |
| `04-opnamen.png` | Library with content, Notities tab, audio kept | 5.6 |
| `04-opnamen-leeg.png` | Library empty state | 5.6 |
| `05-instellingen-algemeen.png` | Settings, Algemeen tab | 5.5 |
| `05-instellingen-notities.png` | Settings, Notities tab | 5.5 |
| `06-over-hush.png` | About window | 5.7 |
| `07-zo-werkt-hush.png` | How to use window | 5.8 |

No images exist for Instellingen › Opname, Opslag and Transcriptie, the onboarding sheet, or the alerts in section 7. Build those from the text spec using the patterns visible in the other images.

---

## 5. Screens in detail

### 5.1 Menu bar icon

- Idle: template glyph `waveform` (monochrome, adapts to menu bar).
- Recording: a filled red dot (`recording`, 9 to 10 px) with the pulse animation.
- While the panel is open, the status item shows the standard highlighted background.

### 5.2 Menubalk · Inactief (screen 1)

Panel 280 px wide, `surface` background, 1 px `border`, radius 8, padding 8, vertical gap 8.

1. **Primary button** full width, 32 px: white filled circle icon, label "Start opname", shortcut "⌥⌘R" right-aligned (regular weight).
2. **Source line** (11 pt secondary, mic icon): "Microfoon: MacBook Pro-microfoon · Uitvoer: systeemaudio". Shows the real device name. If a permission is missing, show a `warning` triangle and the text from section 7, clickable, opening Instellingen › Opname.
3. Divider (full bleed).
4. Section label "Recente opnamen", then the last 3 recordings as rows (28 px): "di 21 okt · 14:00 tot 14:45" plus a badge on the right: **Notities** (notes exist), **Transcript** (transcript only), **Mislukt** (warning icon + text, transcription failed). Clicking a row opens that recording in Opnamen.
5. Divider.
6. Menu rows (24 px) with right-aligned secondary shortcuts: "Open opnamen…" ⌘O, "Instellingen…" ⌘,, "Stop Hush" ⌘Q.

### 5.3 Menubalk · Opname (screen 2)

Same panel, gap 12.

1. Header: pulsing red dot + "Opname sinds 16:10" (11 pt semibold secondary). Below it the elapsed timer "00:23:41" in SF Mono 32 pt, `recording` colour, updating every second.
2. Two level meters, each a row: icon (mic / speaker), label 48 px wide ("Jij", "Anderen"), 4 px high track in `border` with a live fill. Jij fill = `accent`, Anderen fill = `textSecondary`. Update at roughly 15 to 30 fps from RMS levels.
3. Silence warning (only when one source has been silent more than 60 s): warning triangle + "Al 1 min geen geluid van Anderen" (or "van Jij"), 11 pt `warning`. The minute count updates.
4. **Stop opname**: full width 32 px, transparent background, 1 px `recording` outline, red square icon, `textPrimary` semibold label, shortcut "⌥⌘R" secondary.
5. **Pauzeer** / **Hervat**: full width 32 px secondary button with pause / play icon. While paused, the timer stops and the dot stops pulsing (show it at 45% opacity).
6. Divider, then "Open opnamen…", "Instellingen…", "Stop Hush" as in idle.

### 5.4 Na de opname (screens 3.1 to 3.5)

One window, 560 × 520, not resizable, `background` colour, title bar text "Hush" (13 pt semibold secondary, centred). It opens automatically when a recording stops.

**Step indicator** (top, padding 16): 5 equal columns, gap 8. Each column = 4 px bar (radius 2) + 11 pt label below.

| State | Bar | Label |
| --- | --- | --- |
| Completed | `accent` | `textSecondary` with a 12 pt `success` checkmark before it |
| Current | `accent` | `textPrimary` semibold |
| Upcoming | `border` | `textSecondary` |
| Failed | `warning` | `warning` semibold with a warning triangle |

Labels: Transcriberen · Controleren · Notities · Genereren · Afronden.

**Footer**: 1 px top border, padding 16, buttons 28 px. Primary button rightmost. "Vorige" is allowed on steps 2 and 3 only (not after notes are sent).

#### 3.1 Transcriberen

Content centred vertically, side padding 48.

- Title: recording title "di 21 okt · 14:00 tot 14:45". Secondary: "45 min · Microfoon en systeemaudio".
- Panel (`surface`, border, radius 8, padding 16): "Bezig met transcriberen…" left, percentage right (secondary, tabular). Determinate progress bar 6 px (`border` track, `accent` fill). Below: "Nog ongeveer 1 min" (estimate, secondary 11 pt).
- Lock icon + "Transcriptie op deze Mac. Er wordt niets geüpload." (secondary).
- Footer: left hint "Annuleren stopt de transcriptie, de audio blijft bewaard." Buttons: **Annuleer** (secondary, stops transcription, keeps audio, closes window) and **Op de achtergrond** (primary, closes window, keeps transcribing, sends a notification when done which reopens the window at step 2).

#### 3.2 Controleren

- Header: "Transcript controleren", secondary line "di 21 okt · 14:00 tot 14:45 · Jij en Anderen", and a small outlined tag "Alleen lezen" on the right.
- Transcript panel fills the remaining height, scrollable, SF Mono 12 pt. Each line is a 3-column grid: timestamp (64 px, secondary, `00:00:04`), speaker (56 px, semibold, **Jij** in `accent`, **Anderen** in `textSecondary`), text (`textPrimary`, wraps). Read only, text selectable.
- Footer: **Kopieer** (copy icon, copies the whole transcript as plain text), **Toon in Finder** (folder icon), spacer, **Vorige**, **Volgende** (primary).

#### 3.3 Notities

Side padding 48, top 24, gap 16.

- Title "Notities maken van dit transcript?", secondary "di 21 okt · 14:00 tot 14:45 · 45 min".
- **Segmented control**, full width, 3 options: **Claude**, **ChatGPT**, **Overslaan**. Container `surface` + border, radius 8, padding 2; selected segment `accentFill` with white semibold text. Default: last used provider (first run: Claude).
- Participants (hidden when Overslaan): label "Wie waren er nog meer bij dit gesprek?" and a token field (`surfaceRaised`, border, radius 6). Type a name and press Enter to add a token (`border` background, radius 4, 12 pt, × button with accessibility label "Verwijder {naam}"). Placeholder "Typ een naam en druk op Enter". Remember recent names for autocomplete.
- Info line (info icon, 11 pt secondary), changes with the choice:
  - Claude: "Het transcript wordt naar Anthropic gestuurd. De audio blijft op deze Mac."
  - ChatGPT: "Het transcript wordt naar OpenAI gestuurd. De audio blijft op deze Mac."
  - Overslaan: "Er wordt niets verstuurd. Je kunt later notities maken vanuit Opnamen."
- Missing key (only for Claude / ChatGPT when no key is saved): warning row "Nog geen API-sleutel voor Claude." + link "Voeg een Claude-sleutel toe in Instellingen" (opens Instellingen › Notities). The primary button is then disabled (`surfaceRaised` background, `disabledText`).
- Footer: **Vorige** on the left, primary on the right with label "Stuur naar Claude" / "Stuur naar ChatGPT" / "Ga door zonder notities". Overslaan goes straight to step 3.5.

#### 3.4 Genereren

- While waiting: centred spinner (24 px, `accent` arc on `border` ring), "Wachten op Claude…" (15 pt semibold), secondary "Het transcript is naar Anthropic gestuurd. De audio blijft op deze Mac." "Volgende" is disabled. Use "ChatGPT" / "OpenAI" when that was chosen.
- When done: header "Gespreksnotities" + secondary date line, and on the right a success check + "Gemaakt door Claude". Below it a scrollable panel with the notes rendered as Markdown (headings 13 to 15 pt semibold, bullets, bold). Footer: **Kopieer** (copies Markdown), **Open** (opens `notities.md` in the default app), spacer, **Volgende** (primary). No Vorige.
- Request timeout: 120 s. On failure go to state 3.4 fout.

#### 3.5 Afronden

Side padding 48.

- Title "Alles is bewaard", secondary date line.
- Panel with one 40 px row per saved item, each with a `success` check, label and the file name in SF Mono 11 pt secondary: Transcript `transcript.txt`, Notities `notities.md` (only if notes were made), Audio `audio.m4a`.
- Folder row: folder icon, path in SF Mono 12 pt secondary ("~/Documents/Hush/2026-10-21 14.00"), small button **Toon**.
- Divider, then a checkbox, **ticked by default** (follows the Storage setting): "Verwijder de audio-opname", hint "Transcript en notities blijven bewaard. Je kunt deze standaard wijzigen in Instellingen."
- Footer: **Open in Opnamen** (secondary), **Klaar** (primary). The audio is deleted only when the user presses Klaar or Open in Opnamen with the box ticked. Closing the window with the red button keeps the audio.

#### 3.1 fout · Transcriptie mislukt

- Step 1 shown in the failed state.
- Same title and secondary line as 3.1.
- Warning banner (`warningSurface`, `warningBorder`, radius 8, padding 16, 20 pt warning triangle): bold "Transcriptie mislukt. Je audio is veilig." and below it in `textTertiary` "Probeer het opnieuw, of sluit dit venster en probeer het later vanuit Opnamen."
- Folder icon + path to the audio file (SF Mono 12 pt).
- Footer: **Sluit** (secondary), **Probeer opnieuw** (primary).

#### 3.4 fout · Notities mislukt

- Steps 1 to 3 completed, step 4 failed.
- Title "Gespreksnotities", secondary date line.
- Warning banner: "Kan Claude niet bereiken. Je transcript is bewaard." / "Probeer het opnieuw, gebruik ChatGPT of sla de notities voor nu over."
- Path to `transcript.txt`.
- Footer: **Sla over** (secondary, left, goes to 3.5), spacer, **Gebruik ChatGPT** (secondary, resends to the other provider; label flips to "Gebruik Claude" when ChatGPT failed), **Probeer opnieuw** (primary).

### 5.5 Instellingen (screen 5)

Standard settings window, 640 px wide, title = current tab name. Toolbar row under the title bar with 5 tabs (88 × 48 px, 18 pt icon above an 11 pt label): **Algemeen** (gearshape), **Opname** (mic), **Opslag** (folder), **Transcriptie** (doc.text), **Notities** (text.alignleft). Selected tab: `surfaceRaised` background, icon in `accent`, label primary semibold. 1 px border below the toolbar.

Form layout: two-column grid, labels right-aligned in a 136 px column, 16 px column gap, 12 px row gap, padding 24 × 32. Groups are separated by a full-width 1 px divider. Hints under a control are 11 pt secondary.

**Algemeen** (designed)

| Label | Control | Default |
| --- | --- | --- |
| Je naam | Text field, 240 px. Hint: "Wordt gebruikt als "Jij" in transcripten en notities." | Wim |
| Opstarten | Switch + "Open Hush bij inloggen" | On |
| Dock | Switch + "Toon symbool in het Dock" | Off |
| Sneltoets opname | Shortcut recorder showing key caps (⌥ ⌘ R), **Wijzig** button, **Herstel** text button. Hint: "Start en stopt een opname, overal op je Mac." | ⌥⌘R |

Switches: 32 × 18, on = `accentFill` track with white knob, off = `border` track with `textSecondary` knob.

**Opname** (not drawn, build in the same pattern)

| Label | Control |
| --- | --- |
| Microfoon | Pop-up: "Systeemstandaard" plus all input devices |
| Systeemaudio | Switch + "Neem ook het geluid van je Mac op" (default on) |
| Toegang | Two status rows: "Microfoon" and "Systeemaudio", each with a green check + "Toegestaan" or a **Geef toegang** button |

**Opslag** (not drawn)

| Label | Control |
| --- | --- |
| Map voor opnamen | Path (SF Mono 12 pt) with **Kies…** and **Toon**. Default `~/Documents/Hush` |
| Na afronden | Switch + "Verwijder de audio standaard na afronden" (default on) |

**Transcriptie** (not drawn)

| Label | Control |
| --- | --- |
| Engine | Read-only text "Apple, op het apparaat" |
| Talen | Status: "Nederlands en Engels zijn geïnstalleerd", or a warning + **Download** button when assets are missing |

**Notities** (designed, 640 × 680)

| Label | Control |
| --- | --- |
| Claude API-sleutel | When saved: read-only box with green lock icon, "Bewaard in sleutelhanger", small **Vervang** button inside the box; **Test** button after it. When empty: secure field. |
| Claude-model | Pop-up, 240 px. First item "Standaard (aanbevolen)", then the models returned by the provider or a maintained list. |
| (divider) | |
| OpenAI API-sleutel | Secure field, placeholder "Plak je OpenAI-sleutel", **Test** button. Same saved state as Claude. |
| OpenAI-model | Pop-up, 240 px, "Standaard (aanbevolen)" first. |
| (divider) | |
| Promptsjabloon | Multi-line editor, SF Mono 12 pt, 184 px high. Below it: hint "Variabelen: {naam}, {deelnemers}, {transcript}" and **Herstel standaard** button. |

Footer strip (1 px top border, 11 pt secondary, lock icon): "API-sleutels worden bewaard in je sleutelhanger en zijn na het opslaan niet meer zichtbaar."

**Test** results appear inline under the field: success "Sleutel werkt" (`success` check) or warning "Sleutel werkt niet. Controleer de sleutel en probeer opnieuw."

Default prompt template:

```
Je schrijft privé gespreksnotities voor {naam}.
Deelnemers: {naam}, {deelnemers}.

Schrijf in de taal van het transcript:
1. Een korte samenvatting
2. Besluiten
3. Actiepunten, elk met een eigenaar

Transcript:
{transcript}
```

### 5.6 Opnamen (screen 4)

Two-pane window with a full-height sidebar (traffic lights sit in the sidebar).

**Sidebar** (260 px, `surface`, right border):

- Search field (28 px, `surfaceRaised`, radius 6, magnifier icon), placeholder "Zoek in titels en transcripten". Searches titles and transcript text, results update as you type.
- Groups, newest first: "Vandaag", "Gisteren", then dates like "vr 17 okt". Group label 11 pt semibold secondary.
- Row (radius 6, padding 6 × 8): time range "14:00 tot 14:45" (13 pt) above duration "45 min" / "1 uur" (11 pt secondary). On the right, 14 pt status icons in this order: warning triangle if transcription failed, transcript icon, notes icon, audio icon (waveform) when the audio is kept, or a struck-through waveform in `deletedIcon` when the audio was deleted. Each icon has an accessibility label: "Transcriptie mislukt", "Transcript", "Notities", "Audio bewaard", "Audio verwijderd".
- Selected row: `accentFill` background, white text and icons, duration in `#DCE5F8`.

**Detail pane**:

- Header (padding 16 × 24): title "Dinsdag 21 oktober · 14:00 tot 14:45" (15 pt semibold), secondary "45 min · Met Sanne de Vries, Joris Bakker" (participants only if entered). Buttons right: **Maak notities** (reopens step 3.3 for this recording), **Toon in Finder**, and a 28 px **…** button (accessibility label "Meer acties") with a menu containing "Verwijder opname…" (asks for confirmation, see section 7).
- Segmented tabs below the header: **Notities** (default when notes exist) and **Transcript**. Hide or disable Notities when there are none and default to Transcript.
- Content: notes rendered as Markdown, max width 640, padding 24. Transcript tab uses the same mono 3-column layout as step 3.2.
- Audio bar (only if audio is kept): 48 px, `surface`, top border. Round play button (accessibility label "Speel af" / "Pauzeer"), elapsed time, scrubber (4 px track, `accent` fill, 12 px knob), total time, waveform icon + file name.
- Failed recording: a warning banner at the top of the content: "Transcriptie mislukt. Je audio is veilig." with a **Probeer opnieuw** button.

**Leeg** (no recordings): sidebar shows only a disabled search field. Detail pane centres a 64 px circle (`surface`, border) with a 28 pt waveform glyph, then "Nog geen opnamen" (15 pt semibold) and "Start er een via de menubalk of druk op ⌥⌘R." (secondary). The shortcut in the text follows the user's setting.

### 5.7 Over Hush (screen 6)

360 × 440, only the close button active (minimise and zoom greyed out). Content centred, padding 8 × 32 × 24, gap 16:

- App icon 80 px (rounded square, `surface` with border, `accent` waveform glyph). Replace with the final app icon when available.
- "Hush" 20 pt semibold, "Versie 1.0 (1)" secondary (read from `CFBundleShortVersionString` and `CFBundleVersion`).
- "Neemt je gesprekken op en transcribeert ze op deze Mac. Je audio verlaat je Mac nooit." (`textTertiary`).
- Info panel with two 32 px rows: "Transcriptie" · "Apple, op het apparaat" and "Talen" · "Nederlands, Engels".
- Buttons at the bottom: **Wat is er nieuw** (secondary, opens release notes) and **Zoek naar updates** (primary). If no update mechanism is built in v1, leave out the update button and say so in the PR.

### 5.8 Zo werkt Hush (screen 7)

560 × 520. Shown once after the permission onboarding, and always available from the Help menu ("Zo werkt Hush").

- Title "Zo werkt Hush", secondary "Een geheugensteun voor jezelf. Andere deelnemers zien niets."
- Ordered list of 4 steps. Each has a 24 px numbered circle (`badgeNotesBg`, `badgeNotesText`, 12 pt semibold), a semibold title and a secondary description:
  1. **Start een opname** · "Klik op het Hush-symbool in de menubalk of druk op ⌥⌘R. Hush neemt je microfoon en het geluid van je Mac op."
  2. **Stop als het gesprek klaar is** · "Hush maakt meteen een transcript, helemaal op deze Mac. Er wordt niets geüpload."
  3. **Kies of je notities wilt** · "Laat Claude of ChatGPT notities maken, of sla dit over. Alleen als jij het kiest, gaat het transcript de deur uit."
  4. **Vind alles terug in Opnamen** · "Transcripten en notities staan in ~/Documents/Hush. Doorzoek ze via Open opnamen in het menu."
- Info panel with green lock icon: "Gaat er iets mis, dan blijven je audio en transcript altijd bewaard. Hush verwijdert niets zonder dat jij het kiest."
- Footer: checkbox "Niet meer tonen bij opstarten" (left), **Instellingen…** (secondary), **Begrepen** (primary). The folder path and shortcut follow the user's settings.

---

## 6. Data and files

One folder per recording inside the recordings folder (default `~/Documents/Hush`), named by start time: `2026-10-21 14.00`.

```
2026-10-21 14.00/
  audio.m4a          mixed audio for playback (deleted on request)
  mic.m4a            raw mic track (deleted with audio.m4a)
  system.m4a         raw system track (deleted with audio.m4a)
  transcript.txt     plain text transcript
  notities.md        notes, only if generated
  meta.json          metadata, see below
```

`transcript.txt` line format:

```
[00:00:04] Jij: Oké, laten we beginnen. Hoofdpunt is release 4.2.
[00:00:11] Anderen: Prima. De regressiesuite is groen, behalve checkout.
```

`meta.json` fields: `id`, `start`, `end`, `durationSeconds`, `micDevice`, `systemAudioCaptured`, `participants` (array), `transcriptStatus` (`none` | `inProgress` | `done` | `failed`), `notesProvider` (`claude` | `openai` | null), `notesStatus` (`none` | `done` | `failed`), `audioDeleted` (bool), `appVersion`.

Write audio to disk continuously during recording (not only at stop) so a crash never loses more than a few seconds. The library is built by scanning the folder, so files the user moves or deletes in Finder are reflected on next open.

---

## 7. Errors, empty and edge states

Every message says what is safe and what to do next. Warnings use `warning`, never red. Items marked *new copy* were not drawn on the canvas; use this copy and the existing banner / inline warning patterns.

| Situation | Where | Message and actions |
| --- | --- | --- |
| First launch, no permissions | Onboarding sheet, 2 steps (*new copy*) | Step 1 "Toegang tot je microfoon" · "Hush neemt je eigen stem op via de microfoon." **Geef toegang**, then a live test meter. Step 2 "Toegang tot systeemaudio" · "Zo neemt Hush ook op wat de anderen zeggen." **Geef toegang**, test meter. Then **Volgende**, which opens Zo werkt Hush. |
| Permission revoked later | Menu panel source line, Instellingen › Opname (*new copy*) | "Systeemaudio staat uit. Alleen je microfoon wordt opgenomen." · **Open Instellingen** |
| Disk nearly full (< 2 GB) | Menu panel, above Start opname (*new copy*) | "Weinig schijfruimte. De opname kan eerder stoppen." · **Toch starten** |
| Recorder crashed mid meeting | Notification + banner in Opnamen on next open (*new copy*) | "Hush is onverwacht gestopt. Er is 32 min audio bewaard." · **Transcribeer nu** |
| Transcription failed | Step 3.1 fout, library banner | "Transcriptie mislukt. Je audio is veilig." · **Probeer opnieuw**, **Sluit** |
| No API key for chosen provider | Step 3.3 | Primary disabled, "Nog geen API-sleutel voor Claude." + link "Voeg een Claude-sleutel toe in Instellingen" |
| Notes request failed or timed out | Step 3.4 fout | "Kan Claude niet bereiken. Je transcript is bewaard." · **Probeer opnieuw**, **Gebruik ChatGPT**, **Sla over** |
| Very short recording (< 10 s) | Alert on stop (*new copy*) | "Opname te kort om te bewaren." · **Toch bewaren**, **Verwijder** |
| Quit while recording | Alert (*new copy*) | "Er loopt een opname." · **Stop en bewaar**, **Annuleer** |
| Delete recording | Alert from the … menu (*new copy*) | "Opname verwijderen?" · "Audio, transcript en notities van deze opname worden verwijderd. Dit kan niet ongedaan worden." · **Verwijder**, **Annuleer** |
| Silence > 60 s on one source | Menu panel while recording | "Al 1 min geen geluid van Anderen" (or "van Jij") |
| API key test | Instellingen › Notities (*new copy*) | "Sleutel werkt" / "Sleutel werkt niet. Controleer de sleutel en probeer opnieuw." |
| Language assets missing | Instellingen › Transcriptie (*new copy*) | "Taalbestanden voor Nederlands ontbreken." · **Download** |

---

## 8. Privacy and security requirements

- Audio is never uploaded anywhere. Only `transcript.txt` content plus the participant names and the user's name are sent, and only after the user presses "Stuur naar Claude" or "Stuur naar ChatGPT" for that specific recording.
- No analytics, no telemetry, no crash reporting that includes content.
- API keys only in the Keychain. The UI never shows a saved key again.
- Nothing is deleted without an explicit user action in that moment (the Afronden checkbox counts, closing the window does not).
- Log files, if any, must not contain transcript text or keys.

---

## 9. Dutch string reference

Use these strings exactly. Keys are suggestions for the String Catalog.

### Menu bar

| Key | Dutch |
| --- | --- |
| menu.start | Start opname |
| menu.stop | Stop opname |
| menu.pause | Pauzeer |
| menu.resume | Hervat |
| menu.sources | Microfoon: %@ · Uitvoer: systeemaudio |
| menu.recent | Recente opnamen |
| menu.open | Open opnamen… |
| menu.settings | Instellingen… |
| menu.quit | Stop Hush |
| menu.recordingSince | Opname sinds %@ |
| menu.you | Jij |
| menu.them | Anderen |
| menu.silence | Al %d min geen geluid van %@ |
| badge.notes | Notities |
| badge.transcript | Transcript |
| badge.failed | Mislukt |
| a11y.statusIdle | Hush |
| a11y.statusRecording | Hush, opname loopt |

### Flow

| Key | Dutch |
| --- | --- |
| flow.window | Hush |
| step.transcribe | Transcriberen |
| step.review | Controleren |
| step.notes | Notities |
| step.generate | Genereren |
| step.finish | Afronden |
| flow.sources | %@ · Microfoon en systeemaudio |
| flow.transcribing | Bezig met transcriberen… |
| flow.timeLeft | Nog ongeveer %@ |
| flow.onDevice | Transcriptie op deze Mac. Er wordt niets geüpload. |
| flow.cancelHint | Annuleren stopt de transcriptie, de audio blijft bewaard. |
| flow.cancel | Annuleer |
| flow.background | Op de achtergrond |
| flow.reviewTitle | Transcript controleren |
| flow.readOnly | Alleen lezen |
| flow.youAndThem | Jij en Anderen |
| flow.copy | Kopieer |
| flow.reveal | Toon in Finder |
| flow.back | Vorige |
| flow.next | Volgende |
| flow.notesTitle | Notities maken van dit transcript? |
| flow.skip | Overslaan |
| flow.participants | Wie waren er nog meer bij dit gesprek? |
| flow.participantsPlaceholder | Typ een naam en druk op Enter |
| flow.removeParticipant | Verwijder %@ |
| flow.noticeClaude | Het transcript wordt naar Anthropic gestuurd. De audio blijft op deze Mac. |
| flow.noticeOpenAI | Het transcript wordt naar OpenAI gestuurd. De audio blijft op deze Mac. |
| flow.noticeSkip | Er wordt niets verstuurd. Je kunt later notities maken vanuit Opnamen. |
| flow.noKey | Nog geen API-sleutel voor %@. |
| flow.addKey | Voeg een %@-sleutel toe in Instellingen |
| flow.sendClaude | Stuur naar Claude |
| flow.sendOpenAI | Stuur naar ChatGPT |
| flow.continueNoNotes | Ga door zonder notities |
| flow.waiting | Wachten op %@… |
| flow.sentTo | Het transcript is naar %@ gestuurd. De audio blijft op deze Mac. |
| flow.notesHeader | Gespreksnotities |
| flow.madeBy | Gemaakt door %@ |
| flow.open | Open |
| flow.saved | Alles is bewaard |
| flow.reveal.short | Toon |
| flow.deleteAudio | Verwijder de audio-opname |
| flow.deleteAudioHint | Transcript en notities blijven bewaard. Je kunt deze standaard wijzigen in Instellingen. |
| flow.openInLibrary | Open in Opnamen |
| flow.done | Klaar |
| flow.transcribeFailed | Transcriptie mislukt. Je audio is veilig. |
| flow.transcribeFailedHint | Probeer het opnieuw, of sluit dit venster en probeer het later vanuit Opnamen. |
| flow.close | Sluit |
| flow.retry | Probeer opnieuw |
| flow.notesFailed | Kan %@ niet bereiken. Je transcript is bewaard. |
| flow.notesFailedHint | Probeer het opnieuw, gebruik %@ of sla de notities voor nu over. |
| flow.skipShort | Sla over |
| flow.useOther | Gebruik %@ |

### Library

| Key | Dutch |
| --- | --- |
| lib.title | Opnamen |
| lib.search | Zoek in titels en transcripten |
| lib.today | Vandaag |
| lib.yesterday | Gisteren |
| lib.with | Met %@ |
| lib.makeNotes | Maak notities |
| lib.more | Meer acties |
| lib.delete | Verwijder opname… |
| lib.tabNotes | Notities |
| lib.tabTranscript | Transcript |
| lib.play | Speel af |
| lib.empty | Nog geen opnamen |
| lib.emptyHint | Start er een via de menubalk of druk op %@. |
| a11y.failed | Transcriptie mislukt |
| a11y.audioKept | Audio bewaard |
| a11y.audioDeleted | Audio verwijderd |

### Settings

| Key | Dutch |
| --- | --- |
| set.general | Algemeen |
| set.recording | Opname |
| set.storage | Opslag |
| set.transcription | Transcriptie |
| set.notes | Notities |
| set.name | Je naam |
| set.nameHint | Wordt gebruikt als "Jij" in transcripten en notities. |
| set.startup | Opstarten |
| set.launchAtLogin | Open Hush bij inloggen |
| set.dock | Dock |
| set.showDock | Toon symbool in het Dock |
| set.shortcut | Sneltoets opname |
| set.change | Wijzig |
| set.reset | Herstel |
| set.shortcutHint | Start en stopt een opname, overal op je Mac. |
| set.claudeKey | Claude API-sleutel |
| set.openaiKey | OpenAI API-sleutel |
| set.savedInKeychain | Bewaard in sleutelhanger |
| set.replace | Vervang |
| set.test | Test |
| set.claudeModel | Claude-model |
| set.openaiModel | OpenAI-model |
| set.defaultModel | Standaard (aanbevolen) |
| set.pasteKey | Plak je OpenAI-sleutel |
| set.prompt | Promptsjabloon |
| set.variables | Variabelen: {naam}, {deelnemers}, {transcript} |
| set.resetDefault | Herstel standaard |
| set.keysFooter | API-sleutels worden bewaard in je sleutelhanger en zijn na het opslaan niet meer zichtbaar. |

Dates use Dutch formatting: short weekday and month in lower case ("di 21 okt"), full form in the library header ("Dinsdag 21 oktober"), 24-hour times, ranges with "tot" ("14:00 tot 14:45"). Use `Locale(identifier: "nl_NL")` with a date formatter, not string concatenation of English names.

---

## 10. Out of scope for v1

- Speaker diarization and naming individual voices.
- Automatic detection of Teams, Zoom or Meet calls.
- A local LLM option for notes.
- Editing the transcript in place.
- Light mode and languages other than Dutch for the UI.

---

## 11. Suggested build order

1. Project setup: agent app, tokens, Dutch String Catalog, forced dark appearance, opaque window and panel base views.
2. Menu bar status item and panel (idle and recording states) with fake data.
3. Recording engine: mic + system audio capture to disk, level meters, pause / resume, silence detection, crash-safe writing.
4. Permissions onboarding and Instellingen › Opname.
5. On-device transcription with progress, speaker tags from source, `transcript.txt`.
6. Post recording window, steps 3.1, 3.2, 3.5 and the transcription failure state.
7. Keychain, Instellingen › Notities, Claude and OpenAI clients, steps 3.3 and 3.4 and the notes failure state.
8. Opnamen library: folder scanning, search, detail, audio player, empty state, delete.
9. Remaining settings tabs, Over Hush, Zo werkt Hush, global shortcut, launch at login, Dock toggle.
10. Edge states from section 7, accessibility pass (VoiceOver labels, keyboard navigation, Reduce Motion), contrast check.

## 12. Acceptance checklist

- [ ] Every window, panel and popover is fully opaque; no glass, blur or vibrancy anywhere.
- [ ] All visible text is Dutch and comes from the String Catalog.
- [ ] Red appears only on the recording dot, timer and Stop opname outline.
- [ ] One click starts and one click stops a recording; ⌥⌘R works from any app.
- [ ] Both Jij and Anderen are captured and tagged correctly in the transcript.
- [ ] Transcription runs fully offline (test with networking disabled).
- [ ] Nothing is sent to Anthropic or OpenAI without pressing the Send button for that recording.
- [ ] Audio is deleted only via the Afronden checkbox or Verwijder opname, never on failure or window close.
- [ ] Killing the app mid recording leaves a playable audio file and shows the recovery banner.
- [ ] API keys never appear in plain text after saving, in logs or on disk.
- [ ] All interactive elements are reachable by keyboard and have VoiceOver labels.
- [ ] Text contrast meets WCAG AA.
