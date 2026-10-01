'use client';

/**
 * Message composer with durable drafts.
 *
 * Draft behaviour is the product's differentiator, so it is wired for real:
 *   - every keystroke is debounced into IndexedDB
 *   - the draft is flushed on chat switch and on page hide, because a closed
 *     tab is the most common way people lose a half-written message
 *   - the caret position is restored, so returning to a chat resumes exactly
 *     where you left off
 *
 * ⌘↵ / Ctrl+↵ sends; ↵ inserts a newline. In a messenger used for real work an
 * accidental send is worse than an extra keystroke.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { strings } from '@/lib/i18n/strings';
import { Icon } from '@/components/ui/Icons';
import {
  AUTOSAVE_DEBOUNCE_MS,
  captureRevision,
  loadDraft,
  saveDraft,
} from '@/lib/storage/drafts';

export function Composer({
  chatId,
  onSend,
  disabled,
  onDraftChange,
}: {
  chatId: string;
  onSend: (text: string) => Promise<void>;
  disabled: boolean;
  onDraftChange: (chatId: string, hasText: boolean) => void;
}) {
  const [text, setText] = useState('');
  const [savedIndicator, setSavedIndicator] = useState(false);
  const [sending, setSending] = useState(false);

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const indicatorTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Mirrors `text` so the flush-on-unmount and page-hide handlers can read the
  // latest value without depending on it (which would re-run them on every
  // keystroke). Synced from an effect, never written during render.
  const latest = useRef('');

  useEffect(() => {
    latest.current = text;
  }, [text]);

  // Restore this chat's draft, including the caret position.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const draft = await loadDraft(chatId);
      if (cancelled) return;
      setText(draft?.text ?? '');
      requestAnimationFrame(() => {
        const node = textareaRef.current;
        if (!node) return;
        node.focus();
        const position = draft?.cursorPosition ?? draft?.text.length ?? 0;
        node.setSelectionRange(position, position);
      });
    })();
    return () => {
      cancelled = true;
    };
  }, [chatId]);

  // Flush on chat switch and on unmount: this is the save that matters most.
  useEffect(() => {
    const currentChatId = chatId;
    return () => {
      const pending = latest.current;
      if (pending.trim()) {
        void saveDraft(currentChatId, pending, pending.length);
        void captureRevision(currentChatId, pending, 'chatSwitch');
      }
    };
  }, [chatId]);

  // Flush when the tab is hidden or closed. `visibilitychange` is the reliable
  // signal on mobile, where `beforeunload` often never fires.
  useEffect(() => {
    function flush() {
      const pending = latest.current;
      if (pending.trim()) void saveDraft(chatId, pending, pending.length);
    }
    document.addEventListener('visibilitychange', flush);
    window.addEventListener('beforeunload', flush);
    return () => {
      document.removeEventListener('visibilitychange', flush);
      window.removeEventListener('beforeunload', flush);
    };
  }, [chatId]);

  const scheduleSave = useCallback(
    (value: string, cursor: number) => {
      if (saveTimer.current) clearTimeout(saveTimer.current);
      saveTimer.current = setTimeout(async () => {
        await saveDraft(chatId, value, cursor);
        if (!value.trim()) return;
        setSavedIndicator(true);
        if (indicatorTimer.current) clearTimeout(indicatorTimer.current);
        indicatorTimer.current = setTimeout(() => setSavedIndicator(false), 1800);
      }, AUTOSAVE_DEBOUNCE_MS);
    },
    [chatId],
  );

  function handleChange(event: React.ChangeEvent<HTMLTextAreaElement>) {
    const value = event.target.value;
    setText(value);
    onDraftChange(chatId, value.trim().length > 0);
    scheduleSave(value, event.target.selectionStart ?? value.length);

    // Grow with the content, up to a cap, instead of scrolling a tiny box.
    const node = event.target;
    node.style.height = 'auto';
    node.style.height = `${Math.min(node.scrollHeight, 160)}px`;
  }

  async function send() {
    const value = text.trim();
    if (!value || sending || disabled) return;

    setSending(true);
    // Keep the draft in history: a sent message is still a version the user
    // may want to recover.
    await captureRevision(chatId, value, 'send');
    try {
      await onSend(value);
      setText('');
      onDraftChange(chatId, false);
      await saveDraft(chatId, '', 0);
      if (textareaRef.current) textareaRef.current.style.height = 'auto';
    } finally {
      setSending(false);
    }
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      void send();
    }
  }

  const canSend = text.trim().length > 0 && !sending && !disabled;

  return (
    <div className="border-t border-border bg-bg px-3 py-2">
      <div
        className="h-4 text-[11px] text-text-tertiary transition-opacity"
        style={{ opacity: savedIndicator ? 1 : 0 }}
        aria-live="polite"
      >
        {savedIndicator ? strings.draftSaved : ''}
      </div>

      <div className="flex items-end gap-2">
        <textarea
          ref={textareaRef}
          value={text}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          rows={1}
          disabled={disabled}
          placeholder={strings.messagePlaceholder}
          aria-label={strings.messagePlaceholder}
          className="max-h-40 min-h-9 flex-1 resize-none rounded-lg border border-border bg-bg-elevated px-3 py-2 text-[13px] leading-relaxed text-text outline-none transition-colors focus:border-accent disabled:opacity-50"
        />

        <button
          onClick={send}
          disabled={!canSend}
          title={`${strings.send} (⌘↵)`}
          aria-label={strings.send}
          className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-accent text-accent-contrast transition-colors hover:bg-accent-hover disabled:opacity-35"
        >
          <Icon.Send size={16} />
        </button>
      </div>
    </div>
  );
}
