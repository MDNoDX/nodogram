//  Where the assistant's thinking happens: Google Gemini (cloud, best
//  quality, any language) or Apple Intelligence (on this Mac, private).
//
//  Gemini's free tier lets Google use what is sent to improve its models;
//  enabling billing in Google AI Studio turns that off. Settings → AI
//  Assistant says so before anything is sent.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One request to a model. `schema` asks for JSON in that shape.
struct AIRequest: Sendable {
    var system: String
    var prompt: String
    /// JSON schema, serialised (so the request stays Sendable).
    var schema: Data?
    /// Quick tasks (reviewing a draft) use the fastest model and no reasoning.
    var fast: Bool

    init(system: String, prompt: String, schema: [String: Any]? = nil, fast: Bool = false) {
        self.system = system
        self.prompt = prompt
        self.schema = schema.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        self.fast = fast
    }
}

enum AIError: LocalizedError {
    case noKey, unavailable(String), http(Int, String), empty

    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your free Gemini API key in Settings → AI Assistant."
        case .unavailable(let why): return why
        case .http(429, _): return "Gemini's free limit for now is used up — try again in a minute."
        case .http(let code, let message): return "Gemini error \(code): \(message)"
        case .empty: return "The model returned nothing."
        }
    }
}

protocol AIProvider: Sendable {
    func generate(_ request: AIRequest) async throws -> String
}

// MARK: - Gemini

struct GeminiProvider: AIProvider {
    let key: String
    let model: String
    let fastModel: String

    private static let base = "https://generativelanguage.googleapis.com/v1beta"

    func generate(_ request: AIRequest) async throws -> String {
        let name = request.fast ? fastModel : model
        var config: [String: Any] = ["temperature": request.fast ? 0.4 : 0.9]
        if let data = request.schema, let schema = try? JSONSerialization.jsonObject(with: data) {
            config["responseMimeType"] = "application/json"
            config["responseSchema"] = schema
        }
        // No thinkingConfig: Gemini 3 models reject an explicit budget, and the
        // flash models are fast enough without tuning it.
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": request.system]]],
            "contents": [["role": "user", "parts": [["text": request.prompt]]]],
            "generationConfig": config,
            "safetySettings": ["HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH",
                               "HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_DANGEROUS_CONTENT"]
                .map { ["category": $0, "threshold": "BLOCK_ONLY_HIGH"] },
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        // Retry transient "high demand" (503) and network errors with backoff.
        var lastError: Error = AIError.empty
        for attempt in 0..<4 {
            do {
                var urlRequest = URLRequest(url: URL(string: "\(Self.base)/models/\(name):generateContent")!,
                                            timeoutInterval: request.fast ? 45 : 120)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                urlRequest.httpBody = payload
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                if status == 503 || status == 429 {
                    lastError = AIError.http(status, "busy")
                    try await Task.sleep(for: .seconds(Double(attempt + 1) * 2))
                    continue
                }
                guard status == 200 else {
                    let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "request failed"
                    throw AIError.http(status, message)
                }
                let candidate = (json?["candidates"] as? [[String: Any]])?.first
                let parts = ((candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                let text = parts.compactMap { $0["text"] as? String }.joined()
                if text.isEmpty {
                    // A safety block or MAX_TOKENS leaves no text; say why.
                    let reason = (candidate?["finishReason"] as? String) ?? "no output"
                    throw AIError.unavailable("The model returned nothing (\(reason)).")
                }
                return text
            } catch let error as AIError {
                if case .http(let code, _) = error, code == 503 || code == 429 { lastError = error; continue }
                throw error
            } catch {
                lastError = error
                try? await Task.sleep(for: .seconds(Double(attempt + 1) * 2))
            }
        }
        throw lastError
    }

    /// Picks the best free models this key can use: a strong "flash" model
    /// for analysis and the fastest "flash-lite" for quick checks.
    static func discoverModels(key: String) async throws -> (main: String, fast: String) {
        var request = URLRequest(url: URL(string: "\(base)/models?pageSize=200")!, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "invalid key"
            throw AIError.http(status, message)
        }
        let names = ((json?["models"] as? [[String: Any]]) ?? []).compactMap { model -> String? in
            guard let methods = model["supportedGenerationMethods"] as? [String], methods.contains("generateContent"),
                  let name = model["name"] as? String else { return nil }
            return name.replacingOccurrences(of: "models/", with: "")
        }
        func newest(lite: Bool) -> String? {
            // Highest gemini-N.M-flash(-lite); the -latest aliases are tried first.
            let candidates = names.filter { n in
                n.hasPrefix("gemini-") && n.contains("flash")
                    && (lite ? n.contains("lite") : !n.contains("lite"))
                    && !n.contains("image") && !n.contains("tts") && !n.contains("audio")
                    && !n.contains("live") && !n.contains("omni") && !n.contains("2.0") && !n.contains("2.5")
            }
            func version(_ n: String) -> Double {
                guard let match = n.range(of: #"gemini-([0-9]+\.?[0-9]*)-flash"#, options: .regularExpression) else { return 0 }
                return Double(n[match].replacingOccurrences(of: "gemini-", with: "").replacingOccurrences(of: "-flash", with: "")) ?? 0
            }
            return candidates.sorted { version($0) < version($1) }.last
        }
        // Stable aliases always point to the current model and never retire.
        let main = names.contains("gemini-flash-latest") ? "gemini-flash-latest"
            : newest(lite: false) ?? names.first { $0.contains("flash") && !$0.contains("lite") } ?? "gemini-flash-latest"
        let fast = names.contains("gemini-flash-lite-latest") ? "gemini-flash-lite-latest"
            : newest(lite: true) ?? main
        return (main, fast)
    }
}

// MARK: - Apple Intelligence

struct AppleProvider: AIProvider {
    func generate(_ request: AIRequest) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw AIError.unavailable("Apple Intelligence isn't on. Turn it on in System Settings → Apple Intelligence & Siri.")
            }
            var instructions = request.system
            if let data = request.schema, let text = String(data: data, encoding: .utf8) {
                instructions += "\n\nReply with JSON only, matching this schema: \(text)"
            }
            let session = LanguageModelSession(instructions: instructions)
            let reply = try await session.respond(to: request.prompt).content
            return Self.stripFences(reply)
        }
        #endif
        throw AIError.unavailable("Apple Intelligence needs macOS 26.")
    }

    static func stripFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.drop(while: { $0 != "\n" }).dropFirst().description
            if let end = t.range(of: "```", options: .backwards) { t = String(t[..<end.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Settings and key

public enum AssistantSettings {
    public static let providerKey = "ai.provider"            // "gemini" | "apple"
    public static let reviewKey = "ai.reviewBeforeSending"
    public static let depthKey = "ai.historyDepth"
    public static let consentKey = "ai.consentedToCloud"
    public static let mainModelKey = "ai.gemini.model"
    public static let fastModelKey = "ai.gemini.fastModel"

    public static var provider: String { UserDefaults.standard.string(forKey: providerKey) ?? "gemini" }
    public static var reviewsBeforeSending: Bool { UserDefaults.standard.bool(forKey: reviewKey) }
    public static var depth: Int { UserDefaults.standard.object(forKey: depthKey) as? Int ?? 300 }

    static var keyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nodogram/gemini.key")
    }

    /// The Gemini API key, kept in an owner-only file (never in the repo).
    public static var geminiKey: String? {
        guard let text = try? String(contentsOf: keyURL, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    public static func setGeminiKey(_ key: String?) {
        let url = keyURL
        guard let key, !key.isEmpty else { try? FileManager.default.removeItem(at: url); return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? key.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func currentProvider() throws -> AIProvider {
        if provider == "apple" { return AppleProvider() }
        guard let key = geminiKey else { throw AIError.noKey }
        let defaults = UserDefaults.standard
        // Retired 2.5 models (saved by an earlier version) fall back to the
        // stable aliases that always point to the current model.
        func usable(_ stored: String?, _ fallback: String) -> String {
            guard let stored, !stored.isEmpty, !stored.contains("2.5"), !stored.contains("2.0") else { return fallback }
            return stored
        }
        return GeminiProvider(key: key,
                              model: usable(defaults.string(forKey: mainModelKey), "gemini-flash-latest"),
                              fastModel: usable(defaults.string(forKey: fastModelKey), "gemini-flash-lite-latest"))
    }
}
