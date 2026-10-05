//  Settings → AI Assistant: pick the brain (Gemini or Apple Intelligence),
//  add the free key, and turn on review-before-sending.

import AppKit
import SwiftUI
import NodogramDomain
import NodogramUI

struct AssistantPage: View {
    let model: AppModel

    @AppStorage(AssistantSettings.providerKey) private var provider = "gemini"
    @AppStorage(AssistantSettings.reviewKey) private var review = false
    @AppStorage(AssistantSettings.depthKey) private var depth = 300
    @AppStorage(AssistantSettings.consentKey) private var consented = false
    @AppStorage("ai.answerLanguage") private var language = "Uzbek (Latin script)"
    @State private var key = AssistantSettings.geminiKey ?? ""
    @State private var checking = false
    @State private var status: String?
    @State private var ok = false

    var body: some View {
        SettingsForm {
            Section {
                SettingsHero(symbol: "sparkles", tint: SettingsPage.assistant.tint,
                             text: "Understand a person from your chat, get reply ideas in your own style, and have a message checked before you send it.")
            }
            Section("Where it thinks") {
                Picker("Model", selection: $provider) {
                    Text("Google Gemini — best, any language").tag("gemini")
                    Text("Apple Intelligence — on this Mac, private").tag("apple")
                }
                .pickerStyle(.radioGroup)
                if provider == "apple" {
                    Label(model.canSummarize ? "Apple Intelligence is ready." : "Turn on Apple Intelligence in System Settings.",
                          systemImage: model.canSummarize ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(model.canSummarize ? Theme.success : Theme.warning)
                }
            }

            if provider == "gemini" {
                Section {
                    HStack {
                        SecureField("Gemini API key", text: $key)
                        Button(checking ? "…" : "Check & Save") { save() }
                            .disabled(key.isEmpty || checking)
                    }
                    Link("Get a free key at aistudio.google.com", destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.system(size: 12))
                    if let status {
                        Label(status, systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(ok ? Theme.success : Theme.failure)
                    }
                } header: { Text("Gemini key") } footer: {
                    SettingsNote("The key is kept in an owner-only file on this Mac, never in the app's code or any backup you share.")
                }
                Section {
                    Toggle("I understand chat text is sent to Google", isOn: $consented)
                } footer: {
                    SettingsNote("To analyse or review, Nodogram sends the relevant messages' text (no names, numbers, usernames or media) to Google. On Gemini's free tier Google may use it to improve its models and staff may review samples — so don't use Gemini for your most sensitive chats; use Apple Intelligence for those. Enabling billing in Google AI Studio stops that use. Secret and copy-protected chats are never sent.")
                }
            }

            Section("Before sending") {
                Toggle("Check my message with AI before it sends", isOn: $review)
                    .disabled(!model.assistantReady)
                SettingsNote("When on, pressing Send first asks the assistant to look over your message. Most go straight through; it stops you only if something looks off.")
            }

            Section("How it answers") {
                Picker("Reply and advice language", selection: $language) {
                    ForEach(["Uzbek (Latin script)", "Uzbek (Cyrillic)", "Russian", "English", "Same as the chat"], id: \.self) { Text($0) }
                }
                Picker("Messages to read when analysing", selection: $depth) {
                    Text("Last 150").tag(150)
                    Text("Last 300").tag(300)
                    Text("Last 600").tag(600)
                    Text("Last 1000").tag(1000)
                }
            }
        }
        .onAppear { ok = AssistantSettings.geminiKey != nil }
    }

    private func save() {
        checking = true
        status = nil
        Task {
            do {
                let models = try await GeminiProvider.discoverModels(key: key)
                AssistantSettings.setGeminiKey(key)
                UserDefaults.standard.set(models.main, forKey: AssistantSettings.mainModelKey)
                UserDefaults.standard.set(models.fast, forKey: AssistantSettings.fastModelKey)
                ok = true
                status = "Working — using \(models.main)."
            } catch {
                ok = false
                status = (error as? AIError)?.errorDescription ?? error.localizedDescription
            }
            checking = false
        }
    }
}
