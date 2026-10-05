'use client';

import { useMemo } from 'react';
import type { Chat, SidebarDestination } from '@/lib/domain/types';
import { strings } from '@/lib/i18n/strings';
import { shortTimestamp } from '@/lib/format';
import { Avatar } from '@/components/ui/Avatar';
import { EmptyState } from '@/components/ui/EmptyState';
import { Icon } from '@/components/ui/Icons';

export function ChatList({
  chats,
  destination,
  selectedChatId,
  onSelect,
  search,
  onSearch,
  loading,
  draftChatIds,
}: {
  chats: Chat[];
  destination: SidebarDestination;
  selectedChatId?: string;
  onSelect: (chatId: string) => void;
  search: string;
  onSearch: (value: string) => void;
  loading: boolean;
  draftChatIds: Set<string>;
}) {
  const visible = useMemo(() => {
    let list = chats;

    switch (destination) {
      case 'unread':
        list = list.filter((c) => c.unreadCount > 0);
        break;
      case 'personal':
        list = list.filter((c) => c.kind === 'private');
        break;
      case 'groups':
        list = list.filter((c) => c.kind === 'group');
        break;
      case 'channels':
        list = list.filter((c) => c.kind === 'channel');
        break;
      case 'drafts':
        list = list.filter((c) => draftChatIds.has(c.id));
        break;
      default:
        break;
    }

    const query = search.trim().toLowerCase();
    if (query) {
      list = list.filter(
        (c) =>
          c.title.toLowerCase().includes(query) ||
          (c.lastMessage?.text ?? '').toLowerCase().includes(query),
      );
    }
    return list;
  }, [chats, destination, search, draftChatIds]);

  return (
    <div className="flex h-full w-full shrink-0 flex-col border-r border-border bg-bg-list md:w-80">
      <div className="p-2.5">
        <div className="relative">
          <span className="pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2 text-text-tertiary">
            <Icon.Search size={14} />
          </span>
          <input
            value={search}
            onChange={(e) => onSearch(e.target.value)}
            placeholder="Search"
            aria-label="Search conversations"
            className="h-8 w-full rounded-lg border border-transparent bg-bg-hover pr-2.5 pl-8 text-[13px] text-text outline-none transition-colors focus:border-accent focus:bg-bg-elevated"
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        {loading && chats.length === 0 ? (
          <ChatListSkeleton />
        ) : visible.length === 0 ? (
          <EmptyState
            icon={<Icon.Chats size={26} />}
            title={search ? strings.noResults : strings.noChatsTitle}
            message={search ? 'Try a different search.' : strings.noChatsBody}
          />
        ) : (
          <ul role="list">
            {visible.map((chat) => (
              <ChatRow
                key={chat.id}
                chat={chat}
                selected={chat.id === selectedChatId}
                hasDraft={draftChatIds.has(chat.id)}
                onSelect={() => onSelect(chat.id)}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function ChatRow({
  chat,
  selected,
  hasDraft,
  onSelect,
}: {
  chat: Chat;
  selected: boolean;
  hasDraft: boolean;
  onSelect: () => void;
}) {
  const preview = chat.lastMessage;

  // One combined label, so a screen reader reads a sentence rather than a
  // string of unlabelled badges.
  const describedAs = [
    chat.title,
    chat.unreadCount > 0 ? `${chat.unreadCount} unread` : null,
    hasDraft ? 'has draft' : null,
    chat.isMuted ? 'muted' : null,
    preview?.text,
  ]
    .filter(Boolean)
    .join(', ');

  return (
    <li>
      <button
        onClick={onSelect}
        aria-current={selected ? 'true' : undefined}
        aria-label={describedAs}
        className={`flex w-full items-start gap-2.5 px-2.5 py-2 text-left transition-colors ${
          selected ? 'bg-accent-soft' : 'hover:bg-bg-hover'
        }`}
      >
        <Avatar title={chat.title} id={chat.id} size={40} />

        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-1.5">
            <span className="truncate text-[13px] font-semibold text-text">{chat.title}</span>
            {chat.isVerified && (
              <span className="shrink-0 text-accent" title="Verified">
                <Icon.Verified size={12} />
              </span>
            )}
            <span className="ml-auto shrink-0 text-[11px] text-text-tertiary">
              {preview ? shortTimestamp(preview.date) : ''}
            </span>
          </div>

          <div className="mt-0.5 flex items-center gap-1.5">
            {hasDraft && (
              /* Text, not just colour — the indicator must survive greyscale. */
              <span className="shrink-0 text-[11px] font-medium text-warning">Draft</span>
            )}
            {preview?.hasAttachment && (
              <span className="shrink-0 text-text-tertiary" title="Has attachment">
                <Icon.Paperclip size={11} />
              </span>
            )}
            <span className="truncate text-xs text-text-secondary">
              {preview?.isOutgoing ? 'You: ' : ''}
              {preview?.text ?? ''}
            </span>

            <span className="ml-auto flex shrink-0 items-center gap-1">
              {chat.isMuted && (
                <span className="text-text-tertiary" title="Muted">
                  <Icon.Mute size={11} />
                </span>
              )}
              {chat.isPinned && (
                <span className="text-text-tertiary" title="Pinned">
                  <Icon.Pin size={11} />
                </span>
              )}
              {chat.unreadCount > 0 && (
                <span
                  className={`rounded-full px-1.5 text-[10px] font-semibold text-accent-contrast ${
                    chat.isMuted ? 'bg-text-tertiary' : 'bg-accent'
                  }`}
                >
                  {chat.unreadCount > 999 ? '999+' : chat.unreadCount}
                </span>
              )}
            </span>
          </div>
        </div>
      </button>
    </li>
  );
}

/** Shape-matched skeleton, so the list does not jump when real rows arrive. */
function ChatListSkeleton() {
  return (
    <ul className="animate-pulse" aria-hidden="true">
      {Array.from({ length: 8 }).map((_, i) => (
        <li key={i} className="flex items-start gap-2.5 px-2.5 py-2">
          <div className="size-10 shrink-0 rounded-full bg-bg-hover" />
          <div className="flex-1 pt-1">
            <div className="h-2.5 w-1/3 rounded bg-bg-hover" />
            <div className="mt-2 h-2.5 w-3/4 rounded bg-bg-hover" />
          </div>
        </li>
      ))}
    </ul>
  );
}
