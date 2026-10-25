import Foundation

/// All user-facing Dutch strings. Dutch is the only UI language in v1; keys mirror
/// the string reference in the handover so they can move to a String Catalog unchanged.
public enum L10n {
    // Menu bar
    public static let menuStart = "Start opname"
    public static let menuStop = "Stop opname"
    public static let menuPause = "Pauzeer"
    public static let menuResume = "Hervat"
    public static func menuSources(_ device: String) -> String { "Microfoon: \(device) · Uitvoer: systeemaudio" }
    public static let menuRecent = "Recente opnamen"
    public static let menuOpen = "Open opnamen…"
    public static let menuSettings = "Instellingen…"
    public static let menuQuit = "Stop Hush"
    public static func menuRecordingSince(_ time: String) -> String { "Opname sinds \(time)" }
    public static let menuYou = "Jij"
    public static let menuThem = "Anderen"
    public static func menuSilence(minutes: Int, source: String) -> String { "Al \(minutes) min geen geluid van \(source)" }
    public static let badgeNotes = "Notities"
    public static let badgeTranscript = "Transcript"
    public static let badgeFailed = "Mislukt"
    public static let a11yStatusIdle = "Hush"
    public static let a11yStatusRecording = "Hush, opname loopt"

    // Flow
    public static let flowWindow = "Hush"
    public static let stepTranscribe = "Transcriberen"
    public static let stepReview = "Controleren"
    public static let stepNotes = "Notities"
    public static let stepGenerate = "Genereren"
    public static let stepFinish = "Afronden"
    public static func flowSources(_ duration: String) -> String { "\(duration) · Microfoon en systeemaudio" }
    public static let flowTranscribing = "Bezig met transcriberen…"
    public static func flowTimeLeft(_ t: String) -> String { "Nog ongeveer \(t)" }
    public static let flowOnDevice = "Transcriptie op deze Mac. Er wordt niets geüpload."
    public static let flowCancelHint = "Annuleren stopt de transcriptie, de audio blijft bewaard."
    public static let flowCancel = "Annuleer"
    public static let flowBackground = "Op de achtergrond"
    public static let flowReviewTitle = "Transcript controleren"
    public static let flowReadOnly = "Alleen lezen"
    public static let flowYouAndThem = "Jij en Anderen"
    public static let flowCopy = "Kopieer"
    public static let flowReveal = "Toon in Finder"
    public static let flowBack = "Vorige"
    public static let flowNext = "Volgende"
    public static let flowNotesTitle = "Notities maken van dit transcript?"
    public static let flowSkip = "Overslaan"
    public static let flowParticipants = "Wie waren er nog meer bij dit gesprek?"
    public static let flowParticipantsPlaceholder = "Typ een naam en druk op Enter"
    public static func flowRemoveParticipant(_ n: String) -> String { "Verwijder \(n)" }
    public static let flowNoticeClaude = "Het transcript wordt naar Anthropic gestuurd. De audio blijft op deze Mac."
    public static let flowNoticeOpenAI = "Het transcript wordt naar OpenAI gestuurd. De audio blijft op deze Mac."
    public static let flowNoticeSkip = "Er wordt niets verstuurd. Je kunt later notities maken vanuit Opnamen."
    public static func flowNoKey(_ p: String) -> String { "Nog geen API-sleutel voor \(p)." }
    public static func flowAddKey(_ p: String) -> String { "Voeg een \(p)-sleutel toe in Instellingen" }
    public static let flowSendClaude = "Stuur naar Claude"
    public static let flowSendOpenAI = "Stuur naar ChatGPT"
    public static let flowContinueNoNotes = "Ga door zonder notities"
    public static func flowWaiting(_ p: String) -> String { "Wachten op \(p)…" }
    public static func flowSentTo(_ company: String) -> String { "Het transcript is naar \(company) gestuurd. De audio blijft op deze Mac." }
    public static let flowNotesHeader = "Gespreksnotities"
    public static func flowMadeBy(_ p: String) -> String { "Gemaakt door \(p)" }
    public static let flowOpen = "Open"
    public static let flowOpenWord = "Open in Word"
    public static func usageLine(_ u: NotesUsage) -> String {
        let tokens = "\(u.inputTokens.formatted()) in · \(u.outputTokens.formatted()) uit"
        guard let cost = u.costUSD else { return tokens + " tokens" }
        let money = cost < 0.01 ? "< $0,01" : "$" + cost.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "nl_NL")))
        return "\(tokens) tokens · ca. \(money)"
    }
    public static let flowSaved = "Alles is bewaard"
    public static let flowRevealShort = "Toon"
    public static let flowDeleteAudio = "Verwijder de audio-opname"
    public static let flowDeleteAudioHint = "Transcript en notities blijven bewaard. Je kunt deze standaard wijzigen in Instellingen."
    public static let flowOpenInLibrary = "Open in Opnamen"
    public static let flowDone = "Klaar"
    public static let flowTranscribeFailed = "Transcriptie mislukt. Je audio is veilig."
    public static let flowTranscribeFailedHint = "Probeer het opnieuw, of sluit dit venster en probeer het later vanuit Opnamen."
    public static let flowClose = "Sluit"
    public static let flowRetry = "Probeer opnieuw"
    public static func flowNotesFailed(_ p: String) -> String { "Kan \(p) niet bereiken. Je transcript is bewaard." }
    public static func flowNotesFailedHint(_ other: String) -> String { "Probeer het opnieuw, gebruik \(other) of sla de notities voor nu over." }
    public static let flowSkipShort = "Sla over"
    public static func flowUseOther(_ p: String) -> String { "Gebruik \(p)" }

    // Library
    public static let libTitle = "Opnamen"
    public static let libSearch = "Zoek in titels en transcripten"
    public static let libToday = "Vandaag"
    public static let libYesterday = "Gisteren"
    public static func libWith(_ names: String) -> String { "Met \(names)" }
    public static let libMakeNotes = "Maak notities"
    public static let libMore = "Meer acties"
    public static let libDelete = "Verwijder opname…"
    public static let libTabNotes = "Notities"
    public static let libTabTranscript = "Transcript"
    public static let libPlay = "Speel af"
    public static let libPause = "Pauzeer"
    public static let libEmpty = "Nog geen opnamen"
    public static func libEmptyHint(_ shortcut: String) -> String { "Start er een via de menubalk of druk op \(shortcut)." }
    public static let a11yFailed = "Transcriptie mislukt"
    public static let a11yTranscript = "Transcript"
    public static let a11yNotes = "Notities"
    public static let a11yAudioKept = "Audio bewaard"
    public static let a11yAudioDeleted = "Audio verwijderd"

    // Settings
    public static let setGeneral = "Algemeen"
    public static let setRecording = "Opname"
    public static let setStorage = "Opslag"
    public static let setTranscription = "Transcriptie"
    public static let setNotes = "Notities"
    public static let setName = "Je naam"
    public static let setNameHint = "Wordt gebruikt als \"Jij\" in transcripten en notities."
    public static let setStartup = "Opstarten"
    public static let setLaunchAtLogin = "Open Hush bij inloggen"
    public static let setDock = "Dock"
    public static let setShowDock = "Toon symbool in het Dock"
    public static let setShortcut = "Sneltoets opname"
    public static let setChange = "Wijzig"
    public static let setReset = "Herstel"
    public static let setShortcutHint = "Start en stopt een opname, overal op je Mac."
    public static let setClaudeKey = "Claude API-sleutel"
    public static let setOpenAIKey = "OpenAI API-sleutel"
    public static let setSavedInKeychain = "Bewaard in sleutelhanger"
    public static let setReplace = "Vervang"
    public static let setTest = "Test"
    public static let setClaudeModel = "Claude-model"
    public static let setOpenAIModel = "OpenAI-model"
    public static let setDefaultModel = "Standaard (aanbevolen)"
    public static let setPasteClaudeKey = "Plak je Claude-sleutel"
    public static let setPasteOpenAIKey = "Plak je OpenAI-sleutel"
    public static let setPrompt = "Promptsjabloon"
    public static let setVariables = "Variabelen: {naam}, {deelnemers}, {transcript}"
    public static let setResetDefault = "Herstel standaard"
    public static let setKeysFooter = "API-sleutels worden bewaard in je sleutelhanger en zijn na het opslaan niet meer zichtbaar."
    public static let setKeyWorks = "Sleutel werkt"
    public static let setKeyFails = "Sleutel werkt niet. Controleer de sleutel en probeer opnieuw."
    public static let setMicrophone = "Microfoon"
    public static let setSystemDefault = "Systeemstandaard"
    public static let setSystemAudio = "Systeemaudio"
    public static let setSystemAudioToggle = "Neem ook het geluid van je Mac op"
    public static let setAccess = "Toegang"
    public static let testMic = "Test microfoon"
    public static let testSystem = "Test geluid van je Mac"
    public static let testStop = "Stop test"
    public static let testMicListening = "Zeg iets en kijk of de balk beweegt."
    public static let testMicOk = "Je microfoon werkt."
    public static let testMicSilent = "Geen geluid gehoord. Controleer je microfoon of kies een ander apparaat."
    public static let testSystemListening = "Je hoort een kort geluid. Hush luistert mee."
    public static let testSystemOk = "Hush hoort het geluid van je Mac."
    public static let testSystemSilent = "Hush hoorde niets. Staat het volume aan en is toegang tot systeemaudio toegestaan?"
    public static let testSystemFailed = "Kon het geluid van je Mac niet afluisteren. Controleer de toegang tot systeemaudio."
    public static let testLevelMic = "Microfoon"
    public static let testLevelSystem = "Mac"
    public static let setAllowed = "Toegestaan"
    public static let setGrantAccess = "Geef toegang"
    public static let setFolder = "Map voor opnamen"
    public static let setChoose = "Kies…"
    public static let setShow = "Toon"
    public static let setAfterFinish = "Na afronden"
    public static let setDeleteAudioDefault = "Verwijder de audio standaard na afronden"
    public static let setEngine = "Engine"
    public static let setEngineValue = "Apple, op het apparaat"
    public static let setLanguages = "Talen"
    public static let setLanguagesInstalled = "Nederlands en Engels zijn geïnstalleerd"
    public static let setLanguagesMissing = "Taalbestanden voor Nederlands ontbreken."
    public static let setDownload = "Download"
    public static let setSave = "Bewaar"

    // About / help
    public static let aboutTagline = "Neemt je gesprekken op en transcribeert ze op deze Mac. Je audio verlaat je Mac nooit."
    public static func aboutVersion(_ v: String, _ b: String) -> String { "Versie \(v) (\(b))" }
    public static let aboutLanguagesValue = "Nederlands, Engels"
    public static let aboutWhatsNew = "Wat is er nieuw"
    public static let storyMenu = "Wat betekent Hush?"
    public static let storyTitle = "Sst. Hush."
    public static let storyIntro = "Hush is Engels voor “sst”: het geluidje waarmee je iemand vraagt om stil te zijn. Zo werkt de app ook."
    public static let storyBackgroundTitle = "Stil op de achtergrond."
    public static let storyBackgroundBody = "Hush zit in je menubalk. Start een opname, voer je gesprek en vergeet de app."
    public static let storyOthersTitle = "Stil voor de anderen."
    public static let storyOthersBody = "Er komt geen bot in de call en niemand krijgt een melding. De opname is alleen van jou."
    public static let storyPrivateTitle = "Stil over je gesprek."
    public static let storyPrivateBody = "Je audio verlaat je Mac nooit en het transcript maakt je Mac zelf. Alleen als jij op “Stuur naar Claude” of “Stuur naar ChatGPT” drukt, gaat de tekst van dat ene gesprek naar die dienst."
    public static let storyConsent = "Vertel de anderen wel even dat je opneemt."
    public static let storySkip = "Sla animatie over"
    public static let storyStart = "Beginnen"
    public static let storyClose = "Sluiten"
    public static func releaseNotesTitle(_ version: String) -> String { "Nieuw in Hush \(version)" }
    public static let releaseNotesWindow = "Wat is er nieuw?"
    public static func releaseNotesVersion(_ version: String) -> String { "Versie \(version)" }
    public static let helpTitle = "Zo werkt Hush"
    public static let helpSubtitle = "Een geheugensteun voor jezelf. Andere deelnemers zien niets."
    public static let helpStep1Title = "Start een opname"
    public static func helpStep1Body(_ shortcut: String) -> String { "Klik op het Hush-symbool in de menubalk of druk op \(shortcut). Hush neemt je microfoon en het geluid van je Mac op." }
    public static let helpStep2Title = "Stop als het gesprek klaar is"
    public static let helpStep2Body = "Hush maakt meteen een transcript, helemaal op deze Mac. Er wordt niets geüpload."
    public static let helpStep3Title = "Kies of je notities wilt"
    public static let helpStep3Body = "Laat Claude of ChatGPT notities maken, of sla dit over. Alleen als jij het kiest, gaat het transcript de deur uit."
    public static let helpStep4Title = "Vind alles terug in Opnamen"
    public static func helpStep4Body(_ path: String) -> String { "Transcripten en notities staan in \(path). Doorzoek ze via Open opnamen in het menu." }
    public static let helpSafety = "Gaat er iets mis, dan blijven je audio en transcript altijd bewaard. Hush verwijdert niets zonder dat jij het kiest."
    public static let helpDontShow = "Niet meer tonen bij opstarten"
    public static let helpUnderstood = "Begrepen"

    // Errors, edge states
    public static let permSystemAudioOff = "Systeemaudio staat uit. Alleen je microfoon wordt opgenomen."
    public static let permMicOff = "Microfoon staat uit. Hush kan niet opnemen."
    public static let permOpenSettings = "Open Instellingen"
    public static let diskLow = "Weinig schijfruimte. De opname kan eerder stoppen."
    public static let diskStartAnyway = "Toch starten"
    public static func crashRecovered(minutes: Int) -> String { "Hush is onverwacht gestopt. Er is \(minutes) min audio bewaard." }
    public static let crashTranscribeNow = "Transcribeer nu"
    public static let tooShortTitle = "Opname te kort om te bewaren."
    public static let tooShortKeep = "Toch bewaren"
    public static let tooShortDelete = "Verwijder"
    public static let quitWhileRecording = "Er loopt een opname."
    public static let quitStopAndSave = "Stop en bewaar"
    public static let cancel = "Annuleer"
    public static let deleteTitle = "Opname verwijderen?"
    public static let deleteBody = "Audio, transcript en notities van deze opname worden verwijderd. Dit kan niet ongedaan worden."
    public static let deleteConfirm = "Verwijder"
    public static let onbMicTitle = "Toegang tot je microfoon"
    public static let onbMicBody = "Hush neemt je eigen stem op via de microfoon."
    public static let onbSystemTitle = "Toegang tot systeemaudio"
    public static let onbSystemBody = "Zo neemt Hush ook op wat de anderen zeggen."
    public static let notificationDoneTitle = "Transcriptie klaar"
    public static let notificationDoneBody = "Open Hush om het transcript te controleren."
    public static let readOnlyTag = "Alleen lezen"
}

extension L10n {
    public static let keyHelpLink = "Hoe krijg ik een sleutel?"
    public static func keyHelpTitle(_ p: String) -> String { "Een \(p)-sleutel toevoegen" }
    public static let keyHelpIntro = "Hush gebruikt een API-sleutel om je transcript naar het model te sturen. Een Claude Pro- of ChatGPT Plus-abonnement is hiervoor niet genoeg: API-tegoed staat los van je abonnement."
    public static func keyHelpStep1(_ host: String) -> String { "Open \(host) en log in met het account waar je tegoed hebt staan." }
    public static let keyHelpStep2 = "Kies \"Create key\" en geef de sleutel de naam \"Hush\"."
    public static let keyHelpStep3 = "Kopieer de sleutel. Hij is maar één keer zichtbaar."
    public static let keyHelpStep4 = "Kom terug naar Hush en kies \"Plak uit klembord\". Hush controleert en test de sleutel en bewaart hem in je sleutelhanger."
    public static func keyHelpOpen(_ host: String) -> String { "Open \(host)" }
    public static let keyHelpPaste = "Plak uit klembord"
    public static let keyHelpNotAKey = "Het klembord bevat geen geldige sleutel. Kopieer de sleutel en probeer het opnieuw."
    public static let keyHelpCost = "Alleen de tekst van het transcript wordt verstuurd. Een uur gesprek kost meestal een paar cent. Stel in de console eventueel een maandlimiet in."
    public static let keyHelpSaved = "Sleutel bewaard"
    public static let keyHelpClose = "Sluit"
}

extension L10n {
    public static let aboutBuiltBy = "Gebouwd door wswebcreation"
}
