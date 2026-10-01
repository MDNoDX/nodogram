/** Empty states explain what belongs here and offer the action that fills it. */

import type { ReactNode } from 'react';

export function EmptyState({
  icon,
  title,
  message,
  action,
}: {
  icon: ReactNode;
  title: string;
  message: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2.5 p-8 text-center">
      <div className="text-text-tertiary" aria-hidden="true">
        {icon}
      </div>
      <h2 className="text-sm font-semibold text-text">{title}</h2>
      <p className="max-w-80 text-xs leading-relaxed text-text-secondary">{message}</p>
      {action}
    </div>
  );
}
