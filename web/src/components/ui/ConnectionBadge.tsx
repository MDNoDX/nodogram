/** Connection state, shown only when it is not healthy. */

import type { ConnectionState } from '@/lib/domain/types';
import { isWorthShowing } from '@/lib/domain/types';
import { strings } from '@/lib/i18n/strings';
import { Icon } from './Icons';

export function ConnectionBadge({ state }: { state: ConnectionState }) {
  if (!isWorthShowing(state)) return null;

  const entry = {
    connecting: { label: strings.connecting, icon: <Icon.Clock size={11} />, tone: 'text-warning' },
    updating: { label: strings.updating, icon: <Icon.History size={11} />, tone: 'text-warning' },
    offline: { label: strings.offline, icon: <Icon.Offline size={11} />, tone: 'text-danger' },
    connected: { label: strings.connected, icon: <Icon.Check size={11} />, tone: 'text-success' },
  }[state];

  return (
    <div
      className={`flex items-center justify-center gap-1.5 px-2 py-1.5 text-[11px] ${entry.tone}`}
      role="status"
    >
      {entry.icon}
      <span>{entry.label}</span>
    </div>
  );
}
