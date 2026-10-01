/**
 * The draft engine — Nodogram's core differentiator.
 *
 * Telegram keeps one draft per chat and loses it easily. This keeps the draft
 * durable AND keeps its history, so a message you rewrote is recoverable.
 * Everything here is local to this browser; nothing is uploaded.
 */

import { db, toDomainDraft, toDomainRevision } from './db';
import type { Draft, DraftRevision } from '@/lib/domain/types';

/** Matches the macOS app's debounce, so both clients feel the same. */
export const AUTOSAVE_DEBOUNCE_MS = 400;

/** How many prior versions to keep per chat before trimming the oldest. */
const MAX_REVISIONS_PER_CHAT = 50;

/**
 * Saves a draft. A single IndexedDB put, so a crash mid-write leaves either the
 * old draft or the new one — never a torn one.
 */
export async function saveDraft(
  chatId: string,
  text: string,
  cursorPosition: number,
  replyToMessageId?: string,
): Promise<void> {
  if (text.trim().length === 0) {
    await db.drafts.delete(chatId);
    return;
  }
  await db.drafts.put({
    chatId,
    text,
    cursorPosition,
    replyToMessageId,
    updatedAt: Date.now(),
  });
}

export async function loadDraft(chatId: string): Promise<Draft | null> {
  const row = await db.drafts.get(chatId);
  return row ? toDomainDraft(row) : null;
}

export async function loadAllDrafts(): Promise<Draft[]> {
  const rows = await db.drafts.toArray();
  return rows.map(toDomainDraft);
}

export async function deleteDraft(chatId: string): Promise<void> {
  await db.drafts.delete(chatId);
}

/**
 * Records a version in the draft's history.
 *
 * Only called at meaningful boundaries — switching chats, sending, or an
 * explicit save — rather than on every keystroke, which would bury the useful
 * versions in noise. Consecutive identical text is skipped for the same reason.
 */
export async function captureRevision(
  chatId: string,
  text: string,
  reason: DraftRevision['reason'],
): Promise<void> {
  if (text.trim().length === 0) return;

  const latest = await db.draftRevisions
    .where('chatId')
    .equals(chatId)
    .reverse()
    .sortBy('capturedAt');

  if (latest[0]?.text === text) return;

  await db.draftRevisions.add({
    chatId,
    text,
    capturedAt: Date.now(),
    reason,
  });

  // Trim oldest beyond the cap, so history cannot grow without bound.
  if (latest.length >= MAX_REVISIONS_PER_CHAT) {
    const excess = latest.slice(MAX_REVISIONS_PER_CHAT - 1);
    await db.draftRevisions.bulkDelete(
      excess.map((r) => r.id!).filter((id) => id !== undefined),
    );
  }
}

export async function loadRevisions(chatId: string): Promise<DraftRevision[]> {
  const rows = await db.draftRevisions
    .where('chatId')
    .equals(chatId)
    .reverse()
    .sortBy('capturedAt');
  return rows.map(toDomainRevision);
}

export async function clearRevisions(chatId: string): Promise<void> {
  const ids = await db.draftRevisions.where('chatId').equals(chatId).primaryKeys();
  await db.draftRevisions.bulkDelete(ids);
}
