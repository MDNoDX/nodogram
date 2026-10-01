'use client';

import { useEffect, useMemo, useRef } from 'react';
import type { Chat, Message } from '@/lib/domain/types';
import { strings } from '@/lib/i18n/strings';
import { daySeparator, exactTimestamp, messageTime } from '@/lib/format';
import { Avatar } from '@/components/ui/Avatar';
import { EmptyState } from '@/components/ui/EmptyState';
import { Icon } from '@/components/ui/Icons';
import { ReadReceipt } from '@/components/ui/ReadReceipt';

export function Conversation({
  chat,
  messages,
  loading,
}: {
  chat?: Chat;
  messages: Message[];
  loading: boolean;
}) {
  const bottomRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const previousChatId = useRef<string | undefined>(undefined);

  // Jump to the newest message when opening a chat, and follow new arrivals —
  // but only when the user is already near the bottom, so we never yank them
  // away from older messages they are reading.
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const switchedChat = previousChatId.current !== chat?.id;
    previousChatId.current = chat?.id;

    const distanceFromBottom =
      container.scrollHeight - container.scrollTop - container.clientHeight;

    if (switchedChat) {
      bottomRef.current?.scrollIntoView({ block: 'end' });
    } else if (distanceFromBottom < 160) {
      bottomRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
    }
  }, [chat?.id, messages.length]);

  const sections = useMemo(() => groupByDay(messages), [messages]);

  if (!chat) {
    return (
      <EmptyState
        icon={<Icon.Chats size={30} />}
        title={strings.noConversationTitle}
        message={strings.noConversationBody}
      />
    );
  }

  return (
    <div className="flex h-full min-w-0 flex-1 flex-col">
      <header className="flex items-center gap-2.5 border-b border-border bg-bg px-4 py-2.5">
        <Avatar title={chat.title} id={chat.id} size={32} />
        <div className="min-w-0">
          <h1 className="truncate text-sm font-semibold">{chat.title}</h1>
          <p className="text-[11px] text-text-secondary">
            {chat.kind === 'private' ? 'Direct message' : chat.kind === 'group' ? 'Group' : 'Channel'}
          </p>
        </div>
      </header>

      <div ref={containerRef} className="flex-1 overflow-y-auto px-4 py-3">
        {loading && messages.length === 0 ? (
          <MessageSkeleton />
        ) : messages.length === 0 ? (
          <EmptyState
            icon={<Icon.Chats size={26} />}
            title={strings.noMessagesTitle}
            message={strings.noMessagesBody}
          />
        ) : (
          <>
            {sections.map((section) => (
              <section key={section.key}>
                <div className="my-3 flex justify-center">
                  <span className="rounded-full bg-bg-elevated px-2.5 py-0.5 text-[10px] font-semibold tracking-wide text-text-tertiary uppercase">
                    {section.label}
                  </span>
                </div>
                {section.messages.map((message, index) => (
                  <MessageBubble
                    key={message.id}
                    message={message}
                    /* Group consecutive messages from the same sender: repeating
                       the name on every line is visual noise. */
                    showSender={
                      !message.isOutgoing &&
                      chat.kind !== 'private' &&
                      section.messages[index - 1]?.senderName !== message.senderName
                    }
                  />
                ))}
              </section>
            ))}
            <div ref={bottomRef} />
          </>
        )}
      </div>
    </div>
  );
}

function MessageBubble({ message, showSender }: { message: Message; showSender: boolean }) {
  return (
    <div className={`flex ${message.isOutgoing ? 'justify-end' : 'justify-start'} mb-1`}>
      <div
        className={`max-w-[min(68ch,78%)] rounded-xl px-3 py-1.5 ${
          message.isOutgoing ? 'bg-bubble-out' : 'bg-bubble-in'
        }`}
      >
        {showSender && message.senderName && (
          <p className="mb-0.5 text-[11px] font-semibold text-accent">{message.senderName}</p>
        )}

        <p className="text-[13px] leading-relaxed break-words whitespace-pre-wrap text-text">
          {message.text}
        </p>

        <div className="mt-0.5 flex items-center justify-end gap-1.5">
          {message.editDate && (
            <span className="text-[11px] text-text-tertiary">{strings.edited}</span>
          )}
          <time
            className="text-[11px] text-text-tertiary"
            dateTime={message.date.toISOString()}
            title={exactTimestamp(message.date)}
          >
            {messageTime(message.date)}
          </time>
          {message.isOutgoing && (
            <ReadReceipt readDate={message.readDate} sendState={message.sendState} />
          )}
        </div>
      </div>
    </div>
  );
}

function groupByDay(messages: Message[]) {
  const map = new Map<string, Message[]>();
  for (const message of messages) {
    const key = message.date.toDateString();
    const bucket = map.get(key);
    if (bucket) bucket.push(message);
    else map.set(key, [message]);
  }
  return [...map.entries()].map(([key, items]) => ({
    key,
    label: daySeparator(items[0].date),
    messages: items,
  }));
}

function MessageSkeleton() {
  return (
    <div className="animate-pulse space-y-2" aria-hidden="true">
      {[60, 40, 75, 35, 55].map((width, i) => (
        <div key={i} className={`flex ${i % 2 ? 'justify-end' : 'justify-start'}`}>
          <div className="h-8 rounded-xl bg-bg-hover" style={{ width: `${width}%` }} />
        </div>
      ))}
    </div>
  );
}
