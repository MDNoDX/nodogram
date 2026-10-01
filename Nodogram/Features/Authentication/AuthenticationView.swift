//  Login flow, driven by TDLib's authorization state machine.
//
//  The screens mirror TDLib's states rather than imposing our own sequence —
//  any divergence would desynchronise login
//  (Documentation/ARCHITECTURE.md §4).

import SwiftUI
import NodogramDomain
import NodogramUI

public struct AuthenticationView: View {
    private let state: AuthorizationState
    private let errorMessage: String?
    private let isBusy: Bool
    private let onSubmitPhone: (String) -> Void
    private let onSubmitCode: (String) -> Void
    private let onSubmitPassword: (String) -> Void

    @State private var phoneNumber = ""
    @State private var code = ""
    @State private var password = ""

    public init(
        state: AuthorizationState,
        errorMessage: String?,
        isBusy: Bool,
        onSubmitPhone: @escaping (String) -> Void,
        onSubmitCode: @escaping (String) -> Void,
        onSubmitPassword: @escaping (String) -> Void
    ) {
        self.state = state
        self.errorMessage = errorMessage
        self.isBusy = isBusy
        self.onSubmitPhone = onSubmitPhone
        self.onSubmitCode = onSubmitCode
        self.onSubmitPassword = onSubmitPassword
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch state {
            case .waitingForPhoneNumber, .waitingForParameters:
                phoneStep
            case .waitingForCode(let info):
                codeStep(info)
            case .waitingForPassword(let info):
                passwordStep(info)
            case .waitingForRegistration:
                registrationNotice
            case .ready, .loggingOut, .closing, .closed:
                ProgressView().controlSize(.small)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.failure)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(L10n.unofficialDisclosure)
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 400)
        .disabled(isBusy)
        .overlay {
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "lock.rectangle.stack")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(L10n.signIn)
                .font(.system(size: 17, weight: .semibold))
        }
    }

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.phoneNumber, text: $phoneNumber)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitPhone() }

            Text(L10n.phoneHint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)

            Button(L10n.sendCode, action: submitPhone)
                .buttonStyle(.borderedProminent)
                .disabled(phoneNumber.trimmingCharacters(in: .whitespaces).count < 6)
        }
    }

    private func codeStep(_ info: AuthorizationState.CodeInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.verificationCode, text: $code)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSubmitCode(code) }

            Text(deliveryHint(info))
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(L10n.verify) { onSubmitCode(code) }
                .buttonStyle(.borderedProminent)
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// Says where the code actually went, instead of always guessing "SMS".
    private func deliveryHint(_ info: AuthorizationState.CodeInfo) -> String {
        switch info.deliveryHint {
        case .telegramMessage:
            return "Telegram sent the code to your other Telegram apps."
        case .sms:
            return "Telegram sent the code by SMS."
        case .call:
            return "Telegram will call you and read the code aloud."
        case .flashCall:
            return "You'll get a brief call — the code is the calling number."
        case .other:
            return L10n.codeHint
        }
    }

    private func passwordStep(_ info: AuthorizationState.PasswordInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(L10n.twoStepPassword, text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSubmitPassword(password) }

            if let hint = info.hint {
                Text("\(L10n.passwordHintLabel): \(hint)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            Button(L10n.unlock) { onSubmitPassword(password) }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
        }
    }

    private var registrationNotice: some View {
        Text("""
            This phone number isn't registered with Telegram yet. \
            Create the account in an official Telegram app first, then sign in here.
            """)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func submitPhone() {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 6 else { return }
        onSubmitPhone(trimmed)
    }
}
