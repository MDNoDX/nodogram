/**
 * Local-only storage, in the user's own browser.
 *
 * This is the web counterpart of the macOS app's GRDB database, and the same
 * rule governs it (Documentation/DATA_MODEL.md): this store holds data that is
 * *ours*, never a duplicate of Telegram's. Messages are cached here only to
 * make the UI fast offline; drafts, draft history, notes and bookmarks exist
 * nowhere else.
 *
 * Nothing in here is ever sent to a Nodogram server, because there is no
 * Nodogram server. That is the privacy guarantee of the browser architecture.
 */

import Dexie, { type EntityTable } from 'dexie';
import type { Chat, Draft, DraftRevision, Message } from '@/lib/domain/types';

/** A message as persisted. Dates are stored as epoch ms for index-friendliness. */
export interface StoredMessage {
  id: string;
  chatId: string;
  senderId?: string;
  senderName: string;
  text: string;
  date: number;
  editDate?: number;
  isOutgoing: number;
  replyToMessageId?: string;
  hasAttachment: number;
  readDateKind?: string;
  readDateAt?: number;
}

export interface StoredChat {
  id: string;
  title: string;
  kind: string;
  unreadCount: number;
  isPinned: number;
  isMuted: number;
  isVerified: number;
  order: number;
  lastMessageText?: string;
  lastMessageDate?: number;
  lastMessageSender?: string;
  lastMessageOutgoing?: number;
}

export interface StoredDraft {
  chatId: string;
  text: string;
  replyToMessageId?: string;
  cursorPosition: number;
  updatedAt: number;
}

export interface StoredDraftRevision {
  id?: number;
  chatId: string;
  text: string;
  capturedAt: number;
  reason: string;
}

/** A private annotation on a message. Never transmitted. */
export interface StoredNote {
  id?: number;
  chatId: string;
  messageId?: string;
  body: string;
  createdAt: number;
  updatedAt: number;
}

export interface StoredBookmark {
  id?: number;
  chatId: string;
  messageId: string;
  createdAt: number;
}

/** Records that a message was deleted remotely, whether or not we kept it. */
export interface StoredDeletionEvent {
  id?: number;
  chatId: string;
  messageId: string;
  senderName?: string;
  originalDate?: number;
  detectedAt: number;
  retainedText?: string;
}

class NodogramDatabase extends Dexie {
  chats!: EntityTable<StoredChat, 'id'>;
  messages!: EntityTable<StoredMessage, 'id'>;
  drafts!: EntityTable<StoredDraft, 'chatId'>;
  draftRevisions!: EntityTable<StoredDraftRevision, 'id'>;
  notes!: EntityTable<StoredNote, 'id'>;
  bookmarks!: EntityTable<StoredBookmark, 'id'>;
  deletionEvents!: EntityTable<StoredDeletionEvent, 'id'>;

  constructor() {
    super('nodogram');

    // Migrations are append-only: a shipped version is never edited, so an
    // upgrade can never destroy data the user already has.
    this.version(1).stores({
      chats: 'id, order, unreadCount',
      messages: 'id, chatId, date, [chatId+date]',
      drafts: 'chatId, updatedAt',
      draftRevisions: '++id, chatId, capturedAt',
      notes: '++id, chatId, messageId',
      bookmarks: '++id, chatId, messageId, [chatId+messageId]',
      deletionEvents: '++id, chatId, messageId, detectedAt',
    });
  }
}

export const db = new NodogramDatabase();

// ── Mapping between stored rows and domain objects ──────────────────────────

export function toDomainMessage(row: StoredMessage): Message {
  return {
    id: row.id,
    chatId: row.chatId,
    senderId: row.senderId,
    senderName: row.senderName,
    text: row.text,
    date: new Date(row.date),
    editDate: row.editDate ? new Date(row.editDate) : undefined,
    isOutgoing: row.isOutgoing === 1,
    hasAttachment: row.hasAttachment === 1,
    replyToMessageId: row.replyToMessageId,
    readDate: row.readDateKind
      ? row.readDateKind === 'read' && row.readDateAt
        ? { kind: 'read', date: new Date(row.readDateAt) }
        : ({ kind: row.readDateKind } as Message['readDate'])
      : undefined,
  };
}

export function fromDomainMessage(message: Message): StoredMessage {
  return {
    id: message.id,
    chatId: message.chatId,
    senderId: message.senderId,
    senderName: message.senderName,
    text: message.text,
    date: message.date.getTime(),
    editDate: message.editDate?.getTime(),
    isOutgoing: message.isOutgoing ? 1 : 0,
    hasAttachment: message.hasAttachment ? 1 : 0,
    replyToMessageId: message.replyToMessageId,
    readDateKind: message.readDate?.kind,
    readDateAt:
      message.readDate?.kind === 'read'
        ? message.readDate.date.getTime()
        : undefined,
  };
}

export function toDomainChat(row: StoredChat): Chat {
  return {
    id: row.id,
    title: row.title,
    kind: row.kind as Chat['kind'],
    unreadCount: row.unreadCount,
    isPinned: row.isPinned === 1,
    isMuted: row.isMuted === 1,
    isVerified: row.isVerified === 1,
    hasDraft: false,
    order: row.order,
    lastMessage: row.lastMessageText
      ? {
          messageId: '',
          text: row.lastMessageText,
          senderName: row.lastMessageSender,
          date: new Date(row.lastMessageDate ?? 0),
          isOutgoing: row.lastMessageOutgoing === 1,
          hasAttachment: false,
        }
      : undefined,
  };
}

export function fromDomainChat(chat: Chat): StoredChat {
  return {
    id: chat.id,
    title: chat.title,
    kind: chat.kind,
    unreadCount: chat.unreadCount,
    isPinned: chat.isPinned ? 1 : 0,
    isMuted: chat.isMuted ? 1 : 0,
    isVerified: chat.isVerified ? 1 : 0,
    order: chat.order,
    lastMessageText: chat.lastMessage?.text,
    lastMessageDate: chat.lastMessage?.date.getTime(),
    lastMessageSender: chat.lastMessage?.senderName,
    lastMessageOutgoing: chat.lastMessage?.isOutgoing ? 1 : 0,
  };
}

export function toDomainDraft(row: StoredDraft): Draft {
  return {
    chatId: row.chatId,
    text: row.text,
    replyToMessageId: row.replyToMessageId,
    cursorPosition: row.cursorPosition,
    updatedAt: new Date(row.updatedAt),
  };
}

export function toDomainRevision(row: StoredDraftRevision): DraftRevision {
  return {
    id: row.id,
    chatId: row.chatId,
    text: row.text,
    capturedAt: new Date(row.capturedAt),
    reason: row.reason as DraftRevision['reason'],
  };
}
