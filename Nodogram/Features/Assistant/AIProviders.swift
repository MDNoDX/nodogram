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
        var config: [String: Any] = ["temperature": request.fast ? 0.3 : 0.7]
        if let data = request.schema, let schema = try? JSONSerialization.jsonObject(with: data) {
            config["responseMimeType"] = "application/json"
            config["responseSchema"] = schema
        }
        // 2.5 models think by default; quick tasks skip it for speed.
        if name.contains("2.5") { config["thinkingConfig"] = ["thinkingBudget": request.fast ? 0 : 1024] }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": request.system]]],
            "contents": [["role": "user", "parts": [["text": request.prompt]]]],
            "generationConfig": config,
            "safetySettings": ["HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH",
                               "HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_DANGEROUS_CONTENT"]
                .map { ["category": $0, "threshold": "BLOCK_ONLY_HIGH"] },
        ]
        var urlRequest = URLRequest(url: URL(string: "\(Self.base)/models/\(name):generateContent")!, timeoutInterval: request.fast ? 15 : 60)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "request failed"
            throw AIError.http(status, message)
        }
        let parts = (((json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIError.empty }
        return text
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
        let mainPreference = ["gemini-3-flash", "gemini-3-flash-preview", "gemini-flash-latest", "gemini-2.5-flash", "gemini-2.0-flash"]
        let fastPreference = ["gemini-3-flash-lite", "gemini-flash-lite-latest", "gemini-2.5-flash-lite", "gemini-2.0-flash-lite"]
        let main = mainPreference.first(where: names.contains) ?? names.first { $0.contains("flash") && !$0.contains("lite") && !$0.contains("image") && !$0.contains("tts") } ?? "gemini-2.5-flash"
        let fast = fastPreference.first(where: names.contains) ?? main
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
        return GeminiProvider(key: key,
                              model: defaults.string(forKey: mainModelKey) ?? "gemini-2.5-flash",
                              fastModel: defaults.string(forKey: fastModelKey) ?? "gemini-2.5-flash-lite")
    }
}
