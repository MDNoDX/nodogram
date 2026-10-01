/**
 * Translates MTProto objects into Nodogram's domain model.
 *
 * This file and client.ts are the only places that know GramJS exists. Keeping
 * the boundary here means a GramJS upgrade cannot ripple into the UI.
 */

import type { Chat, ChatKind, Message, MessageReadDate } from '@/lib/domain/types';

/* eslint-disable @typescript-eslint/no-explicit-any */

/**
 * GramJS returns BigInteger-like ids. They are normalised to strings so the
 * domain never has to care, and so they can be used as IndexedDB keys.
 */
export function idToString(id: unknown): string {
  if (id === null || id === undefined) return '';
  return String(id);
}

function entityKind(entity: any): ChatKind {
  if (entity?.className === 'Channel') {
    return entity.megagroup ? 'group' : 'channel';
  }
  if (entity?.className === 'Chat') return 'group';
  return 'private';
}

function entityTitle(entity: any): string {
  if (!entity) return 'Unknown';
  if (entity.title) return String(entity.title);
  const first = entity.firstName ?? '';
  const last = entity.lastName ?? '';
  const name = `${first} ${last}`.trim();
  if (name) return name;
  if (entity.username) return String(entity.username);
  return 'Unknown';
}

/** Short, human-readable label for a non-text message. */
function describeMedia(media: any): string | null {
  if (!media) return null;
  switch (media.className) {
    case 'MessageMediaPhoto':
      return 'Photo';
    case 'MessageMediaDocument': {
      const attrs = media.document?.attributes ?? [];
      if (attrs.some((a: any) => a.className === 'DocumentAttributeSticker')) return 'Sticker';
      if (attrs.some((a: any) => a.className === 'DocumentAttributeAudio')) {
        const audio = attrs.find((a: any) => a.className === 'DocumentAttributeAudio');
        return audio?.voice ? 'Voice message' : 'Audio';
      }
      if (attrs.some((a: any) => a.className === 'DocumentAttributeVideo')) return 'Video';
      const filename = attrs.find((a: any) => a.className === 'DocumentAttributeFilename');
      return filename?.fileName ? String(filename.fileName) : 'Document';
    }
    case 'MessageMediaGeo':
    case 'MessageMediaGeoLive':
      return 'Location';
    case 'MessageMediaContact':
      return 'Contact';
    case 'MessageMediaPoll':
      return 'Poll';
    case 'MessageMediaWebPage':
      return null; // The link itself is already in the text.
    default:
      return 'Attachment';
  }
}

export function mapDialogToChat(dialog: any): Chat | null {
  const entity = dialog?.entity;
  if (!entity) return null;

  const id = idToString(entity.id);
  if (!id) return null;

  const message = dialog.message;
  const mediaLabel = describeMedia(message?.media);
  const text: string = message?.message ?? '';

  return {
    id,
    title: entityTitle(entity),
    kind: entityKind(entity),
    unreadCount: Number(dialog.unreadCount ?? 0),
    isPinned: Boolean(dialog.pinned),
    // Telegram expresses "muted" as a notification setting with a future
    // mute-until timestamp; a far-future value is the usual "forever".
    isMuted: Boolean(dialog.dialog?.notifySettings?.muteUntil),
    isVerified: Boolean(entity.verified),
    hasDraft: false,
    order: message?.date ? Number(message.date) : 0,
    lastMessage: message
      ? {
          messageId: idToString(message.id),
          text: text || mediaLabel || '',
          senderName: undefined,
          date: new Date(Number(message.date ?? 0) * 1000),
          isOutgoing: Boolean(message.out),
          hasAttachment: Boolean(mediaLabel),
        }
      : undefined,
  };
}

export function mapMessage(message: any, chatId: string, senderName = ''): Message | null {
  if (!message || message.className === 'MessageEmpty') return null;

  const mediaLabel = describeMedia(message.media);
  const text: string = message.message ?? '';

  return {
    id: idToString(message.id),
    chatId,
    senderId: message.fromId ? idToString(message.fromId.userId ?? message.fromId.channelId) : undefined,
    senderName,
    text: text || mediaLabel || '',
    date: new Date(Number(message.date ?? 0) * 1000),
    editDate: message.editDate ? new Date(Number(message.editDate) * 1000) : undefined,
    isOutgoing: Boolean(message.out),
    hasAttachment: Boolean(mediaLabel),
    replyToMessageId: message.replyTo?.replyToMsgId
      ? idToString(message.replyTo.replyToMsgId)
      : undefined,
    // Read state is resolved separately: an outgoing message's read status comes
    // from the dialog's read-outbox marker, not from the message itself.
    readDate: undefined,
  };
}

/**
 * Derives read state for an outgoing message.
 *
 * MTProto exposes `readOutboxMaxId` — the highest message id the peer has read.
 * That gives a reliable read/unread answer but **no timestamp**, so this
 * returns `tooOld` rather than inventing one. That is the honest mapping: we
 * know it was read, we do not know when.
 */
export function readStateForOutgoing(
  messageId: string,
  readOutboxMaxId: number,
): MessageReadDate {
  const id = Number.parseInt(messageId, 10);
  if (!Number.isFinite(id)) return { kind: 'unread' };
  return id <= readOutboxMaxId ? { kind: 'tooOld' } : { kind: 'unread' };
}
