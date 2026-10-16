import MLX
import MLXLMCommon

/// The fixed start of every cleanup prompt (system prompt + few-shot turns), already run through the model.
///
/// Built once per model load, so each clean only prefills its own user turn. Every clean starts a fresh
/// `ChatSession` from a `copy()` of the cache. MLX caches update functionally, so the stored cache never
/// changes and no dictation can see another's text.
///
/// `@unchecked Sendable` because `[KVCache]` isn't: the arrays are evaluated before it's shared and are only read.
final class PromptPrefix: @unchecked Sendable {
    let tokens: [Int]
    private let cache: [KVCache]

    private init(tokens: [Int], cache: [KVCache]) {
        self.tokens = tokens
        self.cache = cache
    }

    /// A private copy for one generation.
    func cacheCopy() -> [KVCache] { cache.map { $0.copy() } }

    /// The prefix tokens when `full` is exactly `prefix + fragment`, i.e. the chat template renders the
    /// new user turn on its own the same way it does at the end of the whole conversation. Otherwise nil.
    static func split(full: [Int], fragment: [Int]) -> [Int]? {
        guard !fragment.isEmpty, full.count > fragment.count,
              full.suffix(fragment.count).elementsEqual(fragment) else { return nil }
        return Array(full.dropLast(fragment.count))
    }

    /// Prefills `leading` (rendered as the start of a conversation ending in `probe`) into a new cache.
    /// Returns nil if the template can't be split before the last user turn.
    static func build(
        container: ModelContainer,
        leading: [Chat.Message],
        probe: Chat.Message,
        additionalContext: [String: any Sendable]
    ) async throws -> PromptPrefix? {
        try await container.perform(nonSendable: (leading, probe)) { context, messages in
            let (leading, probe) = messages
            let full = try await render(leading + [probe], context: context, additionalContext: additionalContext)
            let fragment = try await render([probe], context: context, additionalContext: additionalContext)
            guard let tokens = split(full: full, fragment: fragment) else { return nil }

            let parameters = GenerateParameters(temperature: 0)
            let cache = try context.model.newCache(parameters: parameters)
            // Creating the iterator prefills every prompt token into `cache` (and samples one token we discard).
            _ = try TokenIterator(
                input: LMInput(tokens: MLXArray(tokens)), model: context.model, cache: cache, parameters: parameters)
            eval(cache.flatMap(\.state))
            guard cache.allSatisfy({ $0.offset == tokens.count }) else { return nil }
            return PromptPrefix(tokens: tokens, cache: cache)
        }
    }

    /// True when `message` rendered after the prefix gives exactly the tokens of the whole conversation,
    /// so starting from the cached prefix is equivalent to prefilling everything.
    func continues(
        into message: Chat.Message,
        leading: [Chat.Message],
        container: ModelContainer,
        additionalContext: [String: any Sendable]
    ) async throws -> Bool {
        let tokens = self.tokens
        return try await container.perform(nonSendable: (leading, message)) { context, messages in
            let (leading, message) = messages
            let full = try await Self.render(leading + [message], context: context, additionalContext: additionalContext)
            let fragment = try await Self.render([message], context: context, additionalContext: additionalContext)
            return Self.split(full: full, fragment: fragment) == tokens
        }
    }

    /// The token ids the chat template produces for `messages`, with the assistant generation prompt,
    /// the same way `ChatSession` renders them.
    private static func render(
        _ messages: [Chat.Message],
        context: ModelContext,
        additionalContext: [String: any Sendable]
    ) async throws -> [Int] {
        let input = UserInput(chat: messages, additionalContext: additionalContext)
        return try await context.processor.prepare(input: input).text.tokens.asArray(Int.self)
    }
}
