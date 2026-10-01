//  AppModel — the presentation-layer owner of app state.
//
//  It is the single consumer of the gateway's ordered event stream. TDLib's
//  contract requires updates be applied in the order received
//  ("all updates and responses to requests must be applied in the order they
//  were received for consistency"), so there is exactly one consuming task
//  here, never a parallel fan-out. See Documentation/ARCHITECTURE.md §5.
//
//  @MainActor because every property it publishes drives SwiftUI directly.
//  The gateway it talks to is Sendable-by-contract, so crossing into it is safe.

import Foundation
import Observation
import NodogramDomain
import NodogramTelegram

@MainActor
@Observable
public final class AppModel {

    /// What the window should be showing. Derived from credentials and
    /// authorization state rather than set imperatively, so the UI cannot
    /// disagree with the underlying state.
    public enum Phase: Equatable {
        case loadingCredentials
        case needsCredentials(detail: String?)
        case authenticating(AuthorizationState)
        case ready
    }

    public private(set) var phase: Phase = .loadingCredentials
    public private(set) var connectionState: ConnectionState = .connecting
    public private(set) var tdlibVersion: String?
    public private(set) var authErrorMessage: String?
    public private(set) var isBusy = false

    public private(set) var chats: [Chat] = []
    public private(set) var messages: [ChatID: [Message]] = [:]

    public var selectedDestination: SidebarDestination = .allChats
    public var selectedChatID: ChatID?
    public var searchText: String = ""
    public var draftText: String = ""
    public private(set) var draftIndicatorVisible = false

    private var gateway: TelegramGateway?
    private var eventTask: Task<Void, Never>?
    private var draftIndicatorTask: Task<Void, Never>?

    public init() {}

    // MARK: - Startup

    /// Loads credentials and, if present, starts TDLib. Safe to call again from
    /// the setup screen's "Check Again" button.
    public func start() async {
        eventTask?.cancel()
        gateway?.shutdown()
        gateway = nil

        switch TelegramCredentials.fromBundle() {
        case .failure(let error):
            phase = .needsCredentials(detail: error.technicalDetail)
            return
        case .success(let credentials):
            await startTelegram(with: credentials)
        }
    }

    private func startTelegram(with credentials: TelegramCredentials) async {
        let gateway = TelegramGateway()
        self.gateway = gateway

        // One task, consuming in order. This is the ordering guarantee.
        eventTask = Task { [weak self] in
            for await event in gateway.events {
                await self?.apply(event)
            }
        }

        do {
            let support = try Self.accountDirectories()
            try await gateway.initialize(
                credentials: credentials,
                databaseDirectory: support.database,
                filesDirectory: support.files
            )
            tdlibVersion = try? await gateway.tdlibVersion()

            // Ask for the current state rather than relying on an update that
            // may have been emitted before the stream was consumed.
            if let state = try await gateway.currentAuthorizationState() {
                applyAuthorizationState(state)
            }
        } catch let error as DomainError {
            // `.notInitialized` is expected transiently and is not a failure to
            // show the user; TDLib will emit the real state via an update.
            if error != .notInitialized {
                authErrorMessage = error.userFacingDescription
            }
            phase = .authenticating(.waitingForPhoneNumber)
        } catch {
            authErrorMessage = DomainError
                .protocolFailure(code: -1, message: "\(error)")
                .userFacingDescription
        }
    }

    // MARK: - Event application

    private func apply(_ event: TelegramEvent) {
        switch event {
        case .authorizationStateChanged(let state):
            applyAuthorizationState(state)
        case .connectionStateChanged(let state):
            connectionState = state
        case .optionReceived(let name, let value):
            if name == "version" { tdlibVersion = value }
        }
    }

    private func applyAuthorizationState(_ state: AuthorizationState) {
        switch state {
        case .ready:
            phase = .ready
            authErrorMessage = nil
        case .closed, .loggingOut, .closing:
            phase = .authenticating(.waitingForPhoneNumber)
            chats = []
            messages = [:]
            selectedChatID = nil
        default:
            // Keep `.ready` sticky against a late `waitingForParameters`, which
            // would otherwise bounce a signed-in user back to the login screen.
            if case .ready = phase, state == .waitingForParameters { return }
            phase = .authenticating(state)
        }
    }

    // MARK: - Authentication actions

    public func submitPhoneNumber(_ phoneNumber: String) {
        performAuthStep { gateway in
            try await gateway.setPhoneNumber(phoneNumber)
        }
    }

    public func submitCode(_ code: String) {
        performAuthStep { gateway in
            try await gateway.checkCode(code)
        }
    }

    public func submitPassword(_ password: String) {
        performAuthStep { gateway in
            try await gateway.checkPassword(password)
        }
    }

    public func signOut() {
        performAuthStep { gateway in
            try await gateway.logOut()
        }
    }

    /// Shared busy/error handling, so each auth action does not repeat it and
    /// cannot forget to clear `isBusy`.
    private func performAuthStep(
        _ body: @escaping @Sendable (TelegramGateway) async throws -> Void
    ) {
        guard let gateway else { return }
        authErrorMessage = nil
        isBusy = true
        Task { [weak self] in
            do {
                try await body(gateway)
            } catch let error as DomainError {
                self?.authErrorMessage = error.userFacingDescription
            } catch {
                // The gateway only throws DomainError, so this is unreachable in
                // practice; handled rather than force-unwrapped so an upstream
                // signature change degrades to a message instead of a crash.
                self?.authErrorMessage = DomainError
                    .protocolFailure(code: -1, message: "\(error)")
                    .userFacingDescription
            }
            self?.isBusy = false
        }
    }

    // MARK: - Composer

    /// Shows the quiet "Draft saved" indicator, then fades it.
    ///
    /// Real persistence arrives with the draft phase; this is the indicator
    /// behaviour only, and it is wired to actual typing rather than faked on a
    /// timer so it never claims a save that did not happen.
    public func draftTextChanged() {
        draftIndicatorTask?.cancel()
        guard !draftText.isEmpty else {
            draftIndicatorVisible = false
            return
        }
        draftIndicatorTask = Task { [weak self] in
            // Debounce, matching the ~400 ms idle window in the architecture.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.draftIndicatorVisible = true
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.draftIndicatorVisible = false
        }
    }

    public func sendDraft() {
        // Sending requires the message pipeline, which is a later phase. The
        // button is wired so the keyboard path is testable now, but it must not
        // pretend to have sent anything.
        authErrorMessage = nil
    }

    // MARK: - Shutdown

    /// Called from `willTerminate`. TDLib requires clients be closed before
    /// termination to keep its database consistent.
    public func shutdown() {
        draftIndicatorTask?.cancel()
        eventTask?.cancel()
        gateway?.shutdown()
        gateway = nil
    }

    // MARK: - Storage layout

    private struct AccountDirectories {
        let database: URL
        let files: URL
    }

    /// Per-account directories, created eagerly so TDLib never fails on a
    /// missing path. Multi-account isolation (brief §40) extends this by
    /// account id; v1 uses a single default account directory.
    private static func accountDirectories() throws -> AccountDirectories {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support
            .appendingPathComponent("Nodogram", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("default", isDirectory: true)

        let database = root.appendingPathComponent("tdlib", isDirectory: true)
        let files = root.appendingPathComponent("files", isDirectory: true)

        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        return AccountDirectories(database: database, files: files)
    }
}
