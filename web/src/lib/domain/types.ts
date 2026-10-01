/**
 * Domain vocabulary for Nodogram Web.
 *
 * Mirrors the macOS app's Swift domain layer (Nodogram/Domain) deliberately:
 * the two clients are separate implementations — Swift and TypeScript cannot
 * share code — but they must not drift in *meaning*. When a concept changes,
 * it changes in both.
 *
 * Nothing here imports GramJS. Protocol types stop at lib/telegram/mapping.ts,
 * which is the same layering rule the macOS app enforces through its package
 * manifest (Documentation/ARCHITECTURE.md §2).
 */

export type ChatId = string;
export type MessageId = string;
export type UserId = string;

/**
 * When a message was read, as far as Telegram is willing to say.
 *
 * The product rule is "do not invent read timestamps when the protocol does not
 * provide them". A timestamp exists ONLY on the `read` variant, so the type
 * itself makes a fabricated time unwritable.
 */
export type MessageReadDate =
  | { kind: 'read'; date: Date }
  | { kind: 'unread' }
  | { kind: 'tooOld' }
  | { kind: 'recipientPrivacyRestricted' }
  | { kind: 'ownPrivacyRestricted' };

export function isRead(readDate: MessageReadDate): boolean {
  return readDate.kind !== 'unread';
}

export function preciseDate(readDate: MessageReadDate): Date | null {
  return readDate.kind === 'read' ? readDate.date : null;
}

/** Distinguishes "they hid it" from "the server forgot" — different UI copy. */
export function isPrivacyWithheld(readDate: MessageReadDate): boolean {
  return (
    readDate.kind === 'recipientPrivacyRestricted' ||
    readDate.kind === 'ownPrivacyRestricted'
  );
}

export type ChatKind = 'private' | 'group' | 'channel';

export interface Chat {
  id: ChatId;
  title: string;
  kind: ChatKind;
  unreadCount: number;
  isPinned: boolean;
  isMuted: boolean;
  isVerified: boolean;
  hasDraft: boolean;
  lastMessage?: MessagePreview;
  /** Telegram's ordering value; higher sorts first. */
  order: number;
}

export interface MessagePreview {
  messageId: MessageId;
  text: string;
  senderName?: string;
  date: Date;
  isOutgoing: boolean;
  hasAttachment: boolean;
}

/**
 * Local send state. Kept separate from server-confirmed read state so the two
 * can never be conflated into a single misleading indicator.
 */
export type MessageSendState =
  | { kind: 'sending' }
  | { kind: 'sent' }
  | { kind: 'failed'; reason: string }
  | { kind: 'offlinePending' };

export interface Message {
  id: MessageId;
  chatId: ChatId;
  senderId?: UserId;
  senderName: string;
  text: string;
  date: Date;
  editDate?: Date;
  isOutgoing: boolean;
  sendState?: MessageSendState;
  readDate?: MessageReadDate;
  replyToMessageId?: MessageId;
  hasAttachment: boolean;
}

export type ConnectionState =
  | 'connected'
  | 'connecting'
  | 'updating'
  | 'offline';

export function isWorthShowing(state: ConnectionState): boolean {
  // A healthy connection needs no indicator; constant banners are noise.
  return state !== 'connected';
}

/** Mirrors the login steps Telegram actually drives. */
export type AuthState =
  | { kind: 'needsCredentials'; detail?: string }
  | { kind: 'loading' }
  | { kind: 'phone' }
  | { kind: 'code'; phoneNumber: string }
  | { kind: 'password'; hint?: string }
  | { kind: 'ready' };

export interface Draft {
  chatId: ChatId;
  text: string;
  replyToMessageId?: MessageId;
  /** Caret position, so returning to a chat resumes exactly where you left. */
  cursorPosition: number;
  updatedAt: Date;
}

/** A prior version of a draft. Local and private; never uploaded. */
export interface DraftRevision {
  id?: number;
  chatId: ChatId;
  text: string;
  capturedAt: Date;
  reason: 'autosave' | 'chatSwitch' | 'send' | 'manual';
}

export type SidebarDestination =
  | 'allChats'
  | 'unread'
  | 'personal'
  | 'groups'
  | 'channels'
  | 'saved'
  | 'archived'
  | 'drafts'
  | 'starred'
  | 'localArchive'
  | 'settings';
