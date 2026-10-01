/**
 * Renders read state honestly.
 *
 * This is the UI half of Nodogram's read-time differentiator. Every outcome the
 * protocol can report gets its own truthful copy, including the ones that mean
 * "we genuinely do not know when". There is no branch that invents a time: the
 * domain type only carries a Date on the `read` variant.
 */

import type { MessageReadDate, MessageSendState } from '@/lib/domain/types';
import { isRead, isPrivacyWithheld } from '@/lib/domain/types';
import { strings } from '@/lib/i18n/strings';
import { Icon } from './Icons';

function formatTime(date: Date): string {
  return date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
}

export function ReadReceipt({
  readDate,
  sendState,
}: {
  readDate?: MessageReadDate;
  sendState?: MessageSendState;
}) {
  // Local send state wins: until the server has the message, there is no
  // server-side read state to report.
  if (sendState && sendState.kind !== 'sent') {
    const map = {
      sending: { label: strings.sending, icon: <Icon.Clock size={12} />, tone: 'text-text-tertiary' },
      failed: { label: strings.failedToSend, icon: <Icon.Warning size={12} />, tone: 'text-danger' },
      offlinePending: { label: strings.queuedOffline, icon: <Icon.Offline size={12} />, tone: 'text-warning' },
    } as const;
    const entry = map[sendState.kind];
    return (
      <span className={`inline-flex items-center gap-1 text-[11px] ${entry.tone}`}>
        {entry.icon}
        {entry.label}
      </span>
    );
  }

  if (!readDate) {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] text-text-tertiary">
        <Icon.Check size={12} />
        {strings.delivered}
      </span>
    );
  }

  const label = (() => {
    switch (readDate.kind) {
      case 'read':
        return `${strings.readAt} ${formatTime(readDate.date)}`;
      case 'unread':
        return strings.delivered;
      case 'tooOld':
        // Honest: we know it was read, Telegram will not say when.
        return strings.readTimeUnavailable;
      case 'recipientPrivacyRestricted':
        return strings.readTimeHiddenByRecipient;
      case 'ownPrivacyRestricted':
        return strings.readTimeHiddenByYou;
    }
  })();

  const tooltip = (() => {
    switch (readDate.kind) {
      case 'read':
        return readDate.date.toLocaleString();
      case 'tooOld':
        return 'Telegram no longer stores when this was read.';
      case 'recipientPrivacyRestricted':
        return 'This person has read receipts turned off.';
      case 'ownPrivacyRestricted':
        return "Telegram only shows you others' read times if you share yours.";
      default:
        return undefined;
    }
  })();

  const read = isRead(readDate);
  // Privacy-withheld states stay muted: they are not an achievement to
  // highlight, and colouring them like a confirmed read would overstate them.
  const tone = read && !isPrivacyWithheld(readDate) ? 'text-accent' : 'text-text-tertiary';

  return (
    <span className={`inline-flex items-center gap-1 text-[11px] ${tone}`} title={tooltip}>
      {read ? <Icon.DoubleCheck size={12} /> : <Icon.Check size={12} />}
      {label}
    </span>
  );
}
