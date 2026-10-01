'use client';

import type { ConnectionState, SidebarDestination } from '@/lib/domain/types';
import { strings } from '@/lib/i18n/strings';
import { Icon } from '@/components/ui/Icons';
import { ConnectionBadge } from '@/components/ui/ConnectionBadge';

const GROUPS: { title: string; items: { id: SidebarDestination; label: string; icon: React.ReactNode }[] }[] = [
  {
    title: 'Chats',
    items: [
      { id: 'allChats', label: strings.allChats, icon: <Icon.Chats size={15} /> },
      { id: 'unread', label: strings.unread, icon: <Icon.Unread size={15} /> },
      { id: 'personal', label: strings.personal, icon: <Icon.Person size={15} /> },
      { id: 'groups', label: strings.groups, icon: <Icon.Group size={15} /> },
      { id: 'channels', label: strings.channels, icon: <Icon.Channel size={15} /> },
      { id: 'saved', label: strings.saved, icon: <Icon.Bookmark size={15} /> },
    ],
  },
  {
    title: 'Organize',
    items: [
      { id: 'archived', label: strings.archived, icon: <Icon.Archive size={15} /> },
      { id: 'drafts', label: strings.drafts, icon: <Icon.Draft size={15} /> },
      { id: 'starred', label: strings.starred, icon: <Icon.Star size={15} /> },
    ],
  },
  {
    title: 'Local',
    items: [
      { id: 'localArchive', label: strings.localArchive, icon: <Icon.History size={15} /> },
      { id: 'settings', label: strings.settings, icon: <Icon.Settings size={15} /> },
    ],
  },
];

export function Sidebar({
  selected,
  onSelect,
  connectionState,
  unreadTotal,
  draftCount,
  onSignOut,
}: {
  selected: SidebarDestination;
  onSelect: (destination: SidebarDestination) => void;
  connectionState: ConnectionState;
  unreadTotal: number;
  draftCount: number;
  onSignOut: () => void;
}) {
  function badgeFor(id: SidebarDestination): number {
    if (id === 'unread' || id === 'allChats') return unreadTotal;
    if (id === 'drafts') return draftCount;
    return 0;
  }

  return (
    <nav
      className="flex h-full w-56 shrink-0 flex-col border-r border-border bg-bg-sidebar"
      aria-label="Sections"
    >
      <div className="flex items-center gap-2 px-3.5 py-3.5">
        <span className="text-accent">
          <Icon.Logo size={18} />
        </span>
        <span className="text-sm font-semibold tracking-tight">Nodogram</span>
      </div>

      <div className="flex-1 overflow-y-auto px-2 pb-2">
        {GROUPS.map((group) => (
          <div key={group.title} className="mb-3">
            <h2 className="px-2 py-1 text-[10px] font-semibold tracking-wide text-text-tertiary uppercase">
              {group.title}
            </h2>
            <ul>
              {group.items.map((item) => {
                const active = item.id === selected;
                const badge = badgeFor(item.id);
                return (
                  <li key={item.id}>
                    <button
                      onClick={() => onSelect(item.id)}
                      aria-current={active ? 'page' : undefined}
                      className={`flex w-full items-center gap-2.5 rounded-md px-2 py-1.5 text-left text-[13px] transition-colors ${
                        active
                          ? 'bg-accent-soft font-medium text-accent'
                          : 'text-text hover:bg-bg-hover'
                      }`}
                    >
                      <span className={active ? 'text-accent' : 'text-text-tertiary'}>
                        {item.icon}
                      </span>
                      <span className="flex-1 truncate">{item.label}</span>
                      {badge > 0 && (
                        <span className="rounded-full bg-accent px-1.5 text-[10px] font-semibold text-accent-contrast">
                          {badge > 999 ? '999+' : badge}
                        </span>
                      )}
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </div>

      <div className="border-t border-border">
        <ConnectionBadge state={connectionState} />
        <button
          onClick={onSignOut}
          className="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-[12px] text-text-secondary transition-colors hover:bg-bg-hover hover:text-danger"
        >
          <Icon.Offline size={14} />
          {strings.signOut}
        </button>
      </div>
    </nav>
  );
}
