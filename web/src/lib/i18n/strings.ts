/**
 * User-facing strings.
 *
 * Centralised so that no string is hard-coded in a component, which is what
 * makes translation possible later without a sweep through the UI. Keys mirror
 * the macOS app's L10n enum so the two clients stay consistent.
 *
 * Launch languages: English, Uzbek (Latin), Uzbek (Cyrillic), Russian.
 */

export const strings = {
  // Navigation
  allChats: 'All Chats',
  unread: 'Unread',
  personal: 'Personal',
  groups: 'Groups',
  channels: 'Channels',
  saved: 'Saved',
  archived: 'Archived',
  drafts: 'Drafts',
  starred: 'Starred',
  localArchive: 'Local Archive',
  settings: 'Settings',

  // Connection
  connected: 'Connected',
  connecting: 'Connecting…',
  updating: 'Syncing…',
  offline: 'Offline',

  // Auth
  signIn: 'Sign in to Telegram',
  phoneNumber: 'Phone number',
  phoneHint: 'Include your country code, for example +998 90 123 45 67.',
  sendCode: 'Send code',
  verificationCode: 'Verification code',
  codeHint: 'Telegram sent a code to your other Telegram apps.',
  verify: 'Verify',
  twoStepPassword: 'Two-step password',
  passwordHint: 'Hint',
  unlock: 'Unlock',
  signOut: 'Sign out',

  // Empty states
  noChatsTitle: 'No conversations yet',
  noChatsBody: 'Chats appear here once Nodogram finishes syncing.',
  noConversationTitle: 'No conversation selected',
  noConversationBody: 'Pick a chat from the list, or press ⌘K to search.',
  noMessagesTitle: 'No messages yet',
  noMessagesBody: 'Messages in this conversation will appear here.',
  noResults: 'No results',
  noDraftHistory: 'No earlier versions of this draft yet.',

  // Composer
  messagePlaceholder: 'Write a message…',
  draftSaved: 'Draft saved',
  send: 'Send',

  // Message metadata
  readAt: 'Read at',
  delivered: 'Delivered',
  readTimeUnavailable: 'Read · time no longer available',
  readTimeHiddenByRecipient: 'Read · time hidden by recipient',
  readTimeHiddenByYou: 'Read · enable your read times to see theirs',
  edited: 'Edited',
  sending: 'Sending…',
  failedToSend: 'Not sent',
  queuedOffline: "Queued — you're offline",

  // Setup
  setupTitle: 'Add your Telegram API credentials',
  setupBody:
    'Nodogram needs its own api_id and api_hash to connect to Telegram.',

  // Required disclosure
  unofficial:
    'Nodogram is an independent, unofficial client. It is not affiliated with, endorsed by, or sponsored by Telegram.',
} as const;

export type StringKey = keyof typeof strings;
