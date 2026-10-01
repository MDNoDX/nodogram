/**
 * Loads chats and messages, and keeps them current.
 *
 * The macOS app gets ordered updates and a local message store from TDLib.
 * GramJS gives neither, so this module provides them:
 *
 *   - Updates are applied through a single serial queue, because applying them
 *     concurrently is how message order and unread counts get corrupted.
 *   - Everything is cached in IndexedDB so a reload paints instantly and the
 *     app stays readable offline.
 */

import type { TelegramClient } from 'telegram';
import type { Chat, Message } from '@/lib/domain/types';
import { db, fromDomainChat, fromDomainMessage, toDomainChat, toDomainMessage } from '@/lib/storage/db';
import { idToString, mapDialogToChat, mapMessage, readStateForOutgoing } from './mapping';

/* eslint-disable @typescript-eslint/no-explicit-any */

export const MESSAGE_PAGE_SIZE = 50;

/** Reads the cached view first, so the UI has something to paint immediately. */
export async function loadCachedChats(): Promise<Chat[]> {
  const rows = await db.chats.orderBy('order').reverse().toArray();
  return rows.map(toDomainChat);
}

export async function loadCachedMessages(chatId: string): Promise<Message[]> {
  const rows = await db.messages.where('chatId').equals(chatId).sortBy('date');
  return rows.map(toDomainMessage);
}

/**
 * Fetches the dialog list and replaces the cache.
 *
 * Pinned chats sort above the rest, then by recency — matching what users
 * expect from every other Telegram client.
 */
export async function fetchChats(client: TelegramClient, limit = 100): Promise<Chat[]> {
  const dialogs = await client.getDialogs({ limit });

  const chats: Chat[] = [];
  for (const dialog of dialogs) {
    const chat = mapDialogToChat(dialog);
    if (chat) chats.push(chat);
  }

  chats.sort((a, b) => {
    if (a.isPinned !== b.isPinned) return a.isPinned ? -1 : 1;
    return b.order - a.order;
  });

  // bulkPut rather than clear+add: replacing the table wholesale would make the
  // list flicker empty on every refresh.
  await db.chats.bulkPut(chats.map(fromDomainChat));

  // Drop chats that no longer exist server-side, so deleted chats do not linger.
  const liveIds = new Set(chats.map((c) => c.id));
  const cachedIds = await db.chats.toCollection().primaryKeys();
  const stale = cachedIds.filter((id) => !liveIds.has(id as string));
  if (stale.length > 0) await db.chats.bulkDelete(stale);

  return chats;
}

/**
 * Fetches recent messages for a chat.
 *
 * Sender names are resolved from the entities GramJS already returns, rather
 * than issuing a request per sender, which would be slow and rate-limited.
 */
export async function fetchMessages(
  client: TelegramClient,
  chatId: string,
  limit = MESSAGE_PAGE_SIZE,
): Promise<Message[]> {
  const entity = await client.getEntity(chatId);
  const raw = await client.getMessages(entity, { limit });

  // The peer's read marker tells us which outgoing messages have been read.
  let readOutboxMaxId = 0;
  try {
    const peer: any = await client.invoke(
      new (await import('telegram')).Api.messages.GetPeerDialogs({
        peers: [entity as any],
      }),
    );
    readOutboxMaxId = Number(peer?.dialogs?.[0]?.readOutboxMaxId ?? 0);
  } catch {
    // Not fatal: without it, outgoing messages simply show as delivered.
  }

  const messages: Message[] = [];
  for (const item of raw) {
    const sender: any = (item as any).sender;
    const senderName = sender
      ? sender.title ?? `${sender.firstName ?? ''} ${sender.lastName ?? ''}`.trim()
      : '';

    const message = mapMessage(item, chatId, senderName);
    if (!message) continue;

    if (message.isOutgoing) {
      message.readDate = readStateForOutgoing(message.id, readOutboxMaxId);
    }
    messages.push(message);
  }

  messages.sort((a, b) => a.date.getTime() - b.date.getTime());
  await db.messages.bulkPut(messages.map(fromDomainMessage));
  return messages;
}

export async function sendMessage(
  client: TelegramClient,
  chatId: string,
  text: string,
  replyToMessageId?: string,
): Promise<Message | null> {
  const entity = await client.getEntity(chatId);
  const sent: any = await client.sendMessage(entity, {
    message: text,
    replyTo: replyToMessageId ? Number.parseInt(replyToMessageId, 10) : undefined,
  });

  const message = mapMessage(sent, chatId, '');
  if (message) {
    message.isOutgoing = true;
    message.sendState = { kind: 'sent' };
    await db.messages.put(fromDomainMessage(message));
  }
  return message;
}

export async function markChatRead(client: TelegramClient, chatId: string): Promise<void> {
  try {
    const entity = await client.getEntity(chatId);
    await client.markAsRead(entity);
    const cached = await db.chats.get(chatId);
    if (cached) await db.chats.put({ ...cached, unreadCount: 0 });
  } catch {
    // Marking read is best-effort; failing it must never block opening a chat.
  }
}

/**
 * A strictly serial update queue.
 *
 * Telegram requires updates be applied in order; running them concurrently
 * corrupts ordering and unread counts. Every handler goes through this chain,
 * and a thrown handler cannot break the chain for later updates.
 */
export class UpdateQueue {
  private tail: Promise<void> = Promise.resolve();

  enqueue(work: () => Promise<void>): void {
    this.tail = this.tail.then(work).catch((error) => {
      console.error('[nodogram] update handler failed', error);
    });
  }

  /** Lets callers await a quiet point — used by tests. */
  async drain(): Promise<void> {
    await this.tail;
  }
}

/**
 * Applies a new incoming message to the cache.
 *
 * Returns the message so the caller can update React state, keeping this module
 * free of any UI dependency.
 */
export async function applyIncomingMessage(update: any): Promise<Message | null> {
  const raw = update?.message;
  if (!raw) return null;

  const peer = raw.peerId;
  const chatId = idToString(peer?.userId ?? peer?.chatId ?? peer?.channelId);
  if (!chatId) return null;

  const message = mapMessage(raw, chatId, '');
  if (!message) return null;

  await db.messages.put(fromDomainMessage(message));

  const chat = await db.chats.get(chatId);
  if (chat) {
    await db.chats.put({
      ...chat,
      order: Math.floor(message.date.getTime() / 1000),
      unreadCount: message.isOutgoing ? chat.unreadCount : chat.unreadCount + 1,
      lastMessageText: message.text,
      lastMessageDate: message.date.getTime(),
      lastMessageOutgoing: message.isOutgoing ? 1 : 0,
    });
  }

  return message;
}

/**
 * Records a remote deletion.
 *
 * The deletion *event* is always kept, even though message content is not
 * retained by default — that is what makes the deletion log useful without
 * turning on retention (Documentation/DATA_MODEL.md).
 */
export async function applyDeletedMessages(update: any): Promise<string[]> {
  const ids: number[] = update?.messages ?? [];
  const deleted: string[] = [];

  for (const numericId of ids) {
    const messageId = idToString(numericId);
    const existing = await db.messages.get(messageId);
    if (!existing) continue;

    await db.deletionEvents.add({
      chatId: existing.chatId,
      messageId,
      senderName: existing.senderName,
      originalDate: existing.date,
      detectedAt: Date.now(),
    });

    await db.messages.delete(messageId);
    deleted.push(messageId);
  }

  return deleted;
}
