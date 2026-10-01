//  Shown when Telegram API credentials are absent.
//
//  This screen exists because credentials deliberately are NOT compiled into
//  the app (Documentation/SECURITY_MODEL.md §7). Rather than failing with an
//  opaque error, Nodogram explains exactly what to do, names the file, and
//  offers to re-check.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct SetupView: View {
    private let detail: String?
    private let onRecheck: () -> Void

    public init(detail: String?, onRecheck: @escaping () -> Void) {
        self.detail = detail
        self.onRecheck = onRecheck
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.accent)

                Text(L10n.setupTitle)
                    .font(.system(size: 17, weight: .semibold))

                Text(L10n.setupBody)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.setupStepsHeader)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.secondaryText)

                SetupStep(number: 1, text: "Sign in at my.telegram.org and open **API development tools**.")
                SetupStep(number: 2, text: "Create an app to get your **api_id** and **api_hash**.")
                SetupStep(number: 3, text: "Copy the template:")
                CodeBlock("cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig")
                SetupStep(number: 4, text: "Fill in both values in `Config/Secrets.xcconfig`.")
                SetupStep(number: 5, text: "Rebuild:")
                CodeBlock("./Tools/build-app.sh")
            }

            if let detail {
                DisclosureGroup("Details") {
                    Text(detail)
                        .font(Theme.Typography.code)
                        .foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.system(size: 11))
            }

            HStack(spacing: 10) {
                Button(L10n.setupOpenPortal) {
                    if let url = URL(string: "https://my.telegram.org") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(L10n.setupRecheck, action: onRecheck)
                    .keyboardShortcut("r", modifiers: .command)
            }

            Text(L10n.unofficialDisclosure)
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 460)
    }
}

private struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 16, height: 16)
                .background(Theme.accentSoft, in: Circle())

            Text(markdown)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Falls back to the raw text if the markdown fails to parse, rather than
    /// showing nothing.
    private var markdown: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct CodeBlock: View {
    let command: String

    init(_ command: String) { self.command = command }

    var body: some View {
        HStack {
            Text(command)
                .font(Theme.Typography.code)
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.listBackground, in: RoundedRectangle(cornerRadius: 5))
        .padding(.leading, 24)
    }
}
