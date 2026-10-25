import Foundation

public enum PromptTemplate {
    public static let defaultTemplate = """
    Je schrijft privé gespreksnotities voor {naam}.
    Deelnemers: {naam}, {deelnemers}.

    Schrijf in de taal van het transcript:
    1. Een korte samenvatting
    2. Besluiten
    3. Actiepunten, elk met een eigenaar

    Transcript:
    {transcript}
    """

    /// Fills `{naam}`, `{deelnemers}` and `{transcript}`. Substitution is single-pass, so a
    /// transcript that happens to contain "{naam}" is never expanded.
    public static func fill(_ template: String, name: String, participants: [String], transcript: String) -> String {
        let values = [
            "{naam}": name,
            "{deelnemers}": participants.joined(separator: ", "),
            "{transcript}": transcript,
        ]
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{",
               let key = values.keys.first(where: { template[index...].hasPrefix($0) }) {
                output += values[key]!
                index = template.index(index, offsetBy: key.count)
            } else {
                output.append(template[index])
                index = template.index(after: index)
            }
        }
        return output
    }

    /// Explains the transcript labels to the model, so it can attribute statements to the named people.
    public static func speakerLegend(name: String, participants: [String]) -> String {
        let me = name.isEmpty ? "de gebruiker" : name
        var line = "Sprekers in dit transcript: \"Jij\" is \(me) (microfoon)"
        switch participants.count {
        case 0: line += "; \"Anderen\" zijn de overige gespreksdeelnemers (systeemaudio)."
        case 1: line += "; \"Anderen\" is \(participants[0]) (systeemaudio)."
        default: line += "; \"Anderen\" zijn \(participants.joined(separator: ", ")) (systeemaudio, niet per persoon te onderscheiden)."
        }
        return line + "\n\n"
    }

    /// The saved notities.md: a short header with who was there, then the model's text.
    public static func notesDocument(body: String, name: String, participants: [String], title: String) -> String {
        var head = title.isEmpty ? "" : "# \(title)\n\n"
        let everyone = ([name] + participants).filter { !$0.isEmpty }
        if !everyone.isEmpty { head += "**Deelnemers:** \(everyone.joined(separator: ", "))\n\n" }
        return head + body
    }
}
