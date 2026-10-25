import Foundation

/// Tokens used by one notes request, with the cost estimated from the price list below.
public struct NotesUsage: Codable, Equatable, Sendable {
    public var model: String
    public var inputTokens: Int
    public var outputTokens: Int

    public init(model: String, inputTokens: Int, outputTokens: Int) {
        self.model = model; self.inputTokens = inputTokens; self.outputTokens = outputTokens
    }

    public var totalTokens: Int { inputTokens + outputTokens }

    /// Estimated cost in US dollars; nil when the model is not in the price list.
    public var costUSD: Double? { ModelPricing.cost(model: model, input: inputTokens, output: outputTokens) }
}

public struct NotesResult: Sendable {
    public var text: String
    public var usage: NotesUsage
    public init(text: String, usage: NotesUsage) { self.text = text; self.usage = usage }
}

/// List prices in US dollars per million tokens (input, output). Update when prices change.
public enum ModelPricing {
    static let table: [(prefix: String, input: Double, output: Double)] = [
        ("claude-fable-5", 10, 50),
        ("claude-opus-5-5", 4, 20),
        ("claude-opus-5", 5, 25),
        ("claude-opus-4", 5, 25),
        ("claude-sonnet-5", 2, 10),
        ("claude-sonnet-4", 3, 15),
        ("claude-haiku-5", 0.10, 0.50),
        ("claude-haiku-4", 1, 5),
        ("gpt-5", 1.25, 10),
    ]

    public static func cost(model: String, input: Int, output: Int) -> Double? {
        guard let p = table.first(where: { model.hasPrefix($0.prefix) }) else { return nil }
        return (Double(input) * p.input + Double(output) * p.output) / 1_000_000
    }
}
