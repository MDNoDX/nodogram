//  Localization keys.
//
//  The brief requires no hard-coded user-facing strings from day one, with keys
//  like `chat.mark_as_read` (brief §55). Launch languages: English, Uzbek
//  (Latin), Uzbek (Cyrillic), Russian.
//
//  Every key is declared here so that (a) typos are compile errors rather than
//  silently-missing translations, and (b) the full set of user-visible strings
//  is enumerable for translators.

import Foundation

public enum L10n {
    /// Looks the key up in the app bundle, falling back to the provided English
    /// text. The fallback means a missing translation degrades to readable
    /// English rather than showing a raw key to the user.
    public static func t(_ key: String, _ fallback: String) -> String {
        let value = Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
        return value.isEmpty ? fallback : value
    }

    // MARK: Navigation
    public static var allChats: String { t("nav.all_chats", "All Chats") }
    public static var unread: String { t("nav.unread", "Unread") }
    public static var personal: String { t("nav.personal", "Personal") }
    public static var groups: String { t("nav.groups", "Groups") }
    public static var channels: String { t("nav.channels", "Channels") }
    public static var saved: String { t("nav.saved", "Saved") }
    public static var archived: String { t("nav.archived", "Archived") }
    public static var drafts: String { t("nav.drafts", "Drafts") }
    public static var media: String { t("nav.media", "Media") }
    public static var files: String { t("nav.files", "Files") }
    public static var links: String { t("nav.links", "Links") }
    public static var voiceMessages: String { t("nav.voice_messages", "Voice Messages") }
    public static var starred: String { t("nav.starred", "Starred") }
    public static var recentlyViewed: String { t("nav.recently_viewed", "Recently Viewed") }
    public static var localArchive: String { t("nav.local_archive", "Local Archive") }
    public static var settings: String { t("nav.settings", "Settings") }

    // MARK: Connection
    public static var connected: String { t("connection.connected", "Connected") }
    public static var connecting: String { t("connection.connecting", "Connecting…") }
    public static var updating: String { t("connection.updating", "Syncing…") }
    public static var offline: String { t("connection.offline", "Offline") }

    // MARK: Authentication
    public static var signIn: String { t("auth.sign_in", "Sign in to Telegram") }
    public static var phoneNumber: String { t("auth.phone_number", "Phone number") }
    public static var phoneHint: String {
        t("auth.phone_hint", "Include your country code, for example +998 90 123 45 67.")
    }
    public static var sendCode: String { t("auth.send_code", "Send Code") }
    public static var verificationCode: String { t("auth.verification_code", "Verification code") }
    public static var codeHint: String {
        t("auth.code_hint", "Telegram sent you a code. Check your other Telegram apps first.")
    }
    public static var verify: String { t("auth.verify", "Verify") }
    public static var twoStepPassword: String { t("auth.two_step_password", "Two-step password") }
    public static var passwordHintLabel: String { t("auth.password_hint_label", "Hint") }
    public static var unlock: String { t("auth.unlock", "Unlock") }
    public static var signOut: String { t("auth.sign_out", "Sign Out") }
    public static var back: String { t("auth.back", "Back") }

    // MARK: Empty states — useful, not decorative (brief §72)
    public static var noChatsTitle: String { t("empty.no_chats.title", "No conversations yet") }
    public static var noChatsBody: String {
        t("empty.no_chats.body", "Chats appear here once you sign in and Nodogram syncs.")
    }
    public static var noConversationTitle: String {
        t("empty.no_conversation.title", "No conversation selected")
    }
    public static var noConversationBody: String {
        t("empty.no_conversation.body", "Pick a chat from the list, or press ⌘K to search.")
    }
    public static var noSearchResults: String { t("empty.no_results", "No results") }
    public static var noDraftHistory: String { t("empty.no_draft_history", "No draft history yet") }
    public static var noArchiveTitle: String {
        t("empty.no_archive.title", "Nothing archived locally")
    }
    public static var noArchiveBody: String {
        t("empty.no_archive.body",
          "When enabled, messages deleted by their sender are kept here — but only ones this Mac already received.")
    }

    // MARK: Setup
    public static var setupTitle: String { t("setup.title", "Add your Telegram API credentials") }
    public static var setupBody: String {
        t("setup.body",
          "Nodogram needs its own api_id and api_hash to connect. These are yours, and they stay on this Mac.")
    }
    public static var setupStepsHeader: String { t("setup.steps_header", "Setup") }
    public static var setupRecheck: String { t("setup.recheck", "Check Again") }
    public static var setupOpenPortal: String { t("setup.open_portal", "Open my.telegram.org") }

    // MARK: Composer
    public static var messagePlaceholder: String { t("composer.placeholder", "Write a message…") }
    public static var draftSaved: String { t("draft.saved", "Draft saved") }
    public static var send: String { t("composer.send", "Send") }

    // MARK: Message metadata
    public static var readAt: String { t("message.read_at", "Read at") }
    public static var delivered: String { t("message.delivered", "Delivered") }
    public static var readTimeUnavailable: String {
        t("message.read_time_unavailable", "Read · time no longer available")
    }
    public static var readTimeHiddenByRecipient: String {
        t("message.read_time_hidden_recipient", "Read · time hidden by recipient")
    }
    public static var readTimeHiddenByYou: String {
        t("message.read_time_hidden_own", "Read · enable your read times to see theirs")
    }
    public static var edited: String { t("message.edited", "Edited") }
    public static var sending: String { t("message.sending", "Sending…") }
    public static var failedToSend: String { t("message.failed", "Not sent") }
    public static var queuedOffline: String { t("message.queued_offline", "Queued — you're offline") }

    // MARK: Unofficial-client disclosure (required, see LEGAL §4)
    public static var unofficialDisclosure: String {
        t("about.unofficial",
          "Nodogram is an independent, unofficial client. It is not affiliated with, endorsed by, or sponsored by Telegram.")
    }
}
