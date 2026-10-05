// Turning Bot API messages into what the vault stores and shows. Pure
// functions, so they are tested without a network or a database.

export function displayName(user) {
  if (!user) return "";
  return [user.first_name, user.last_name].filter(Boolean).join(" ") || (user.username ? `@${user.username}` : "");
}

export function chatTitle(chat) {
  if (!chat) return "";
  return chat.title || [chat.first_name, chat.last_name].filter(Boolean).join(" ") || (chat.username ? `@${chat.username}` : "");
}

/** The kind of media, the file to keep (largest photo size), and a label. */
export function mediaOf(message) {
  const pick = (kind, file, label) => ({ kind, fileId: file.file_id, fileUniqueId: file.file_unique_id, size: file.file_size ?? 0, label });
  if (message.photo?.length) return pick("photo", message.photo[message.photo.length - 1], "Photo");
  if (message.video) return pick("video", message.video, "Video");
  if (message.animation) return pick("animation", message.animation, "GIF");
  if (message.voice) return pick("voice", message.voice, "Voice message");
  if (message.video_note) return pick("video_note", message.video_note, "Video message");
  if (message.audio) return pick("audio", message.audio, "Audio");
  if (message.sticker) return pick("sticker", message.sticker, `${message.sticker.emoji ?? ""} Sticker`.trim());
  if (message.document) return pick("document", message.document, message.document.file_name || "File");
  if (message.contact) return { kind: "contact", label: "Contact" };
  if (message.location) return { kind: "location", label: "Location" };
  if (message.poll) return { kind: "poll", label: "Poll" };
  return null;
}

/** Everything the vault keeps about one message. */
export function toRecord(message, ownerId) {
  const media = mediaOf(message);
  const text = message.text ?? message.caption ?? (message.poll ? message.poll.question : "") ?? "";
  return {
    chatId: message.chat.id,
    messageId: message.message_id,
    connectionId: message.business_connection_id,
    chatTitle: chatTitle(message.chat),
    chatUsername: message.chat.username ?? "",
    senderId: message.from?.id ?? null,
    senderName: displayName(message.from),
    isOutgoing: message.from?.id === ownerId || Boolean(message.sender_business_bot),
    date: message.date,
    text,
    mediaKind: media?.kind ?? null,
    mediaLabel: media?.label ?? null,
    fileId: media?.fileId ?? null,
    fileUniqueId: media?.fileUniqueId ?? null,
    fileSize: media?.size ?? 0,
    isProtected: Boolean(message.has_protected_content),
    replyTo: message.reply_to_message?.message_id ?? null,
    raw: message,
  };
}

const escapeHTML = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const time = (d) => new Date(d).toLocaleString("en-GB", {
  hour: "2-digit", minute: "2-digit", day: "2-digit", month: "short", timeZone: process.env.TZ || undefined,
});

/** The owner's notification for a deleted message, as Telegram HTML. */
export function deletedNotice(row) {
  const who = escapeHTML(row.sender_name || row.chat_title || "Someone");
  const link = row.chat_username ? ` (<a href="https://t.me/${escapeHTML(row.chat_username)}">@${escapeHTML(row.chat_username)}</a>)` : "";
  const label = row.media_kind ? `<i>${escapeHTML(labelFor(row))}</i>\n` : "";
  const body = row.text ? `<blockquote expandable>${escapeHTML(row.text).slice(0, 3500)}</blockquote>` : "";
  return `🗑 <b>${who}</b>${link} deleted a message\n${label}${body}\n<i>sent ${time(row.sent_at)} · deleted ${time(row.deleted_at ?? new Date())}</i>`;
}

/** The owner's notification for an edit: what it said before, and now. */
export function editedNotice(name, username, before, after) {
  const link = username ? ` (@${escapeHTML(username)})` : "";
  return `✏️ <b>${escapeHTML(name || "Someone")}</b>${link} edited a message\n` +
    `<b>Before:</b><blockquote expandable>${escapeHTML(before).slice(0, 1700)}</blockquote>` +
    `<b>Now:</b><blockquote expandable>${escapeHTML(after).slice(0, 1700)}</blockquote>`;
}

export function labelFor(row) {
  const labels = { photo: "Photo", video: "Video", animation: "GIF", voice: "Voice message", video_note: "Video message",
    audio: "Audio", sticker: "Sticker", document: "File", contact: "Contact", location: "Location", poll: "Poll" };
  return labels[row.media_kind] ?? "Message";
}

/** Bot API method and field to re-send a kind of media. */
export function resendMethod(kind) {
  return {
    photo: ["sendPhoto", "photo"], video: ["sendVideo", "video"], animation: ["sendAnimation", "animation"],
    voice: ["sendVoice", "voice"], video_note: ["sendVideoNote", "video_note"], audio: ["sendAudio", "audio"],
    sticker: ["sendSticker", "sticker"], document: ["sendDocument", "document"],
  }[kind] ?? null;
}
