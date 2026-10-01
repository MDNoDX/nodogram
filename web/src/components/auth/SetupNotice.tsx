'use client';

/**
 * Shown when the Telegram API credentials are missing.
 *
 * Credentials are intentionally not baked into the repository, so this is the
 * expected first-run state rather than an error. It names the exact variables
 * and both places they can be set.
 */

import { useState } from 'react';
import { strings } from '@/lib/i18n/strings';
import { Icon } from '@/components/ui/Icons';

export function SetupNotice({ detail }: { detail?: string }) {
  const [copied, setCopied] = useState<string | null>(null);

  const snippet =
    'NEXT_PUBLIC_TELEGRAM_API_ID=1234567\nNEXT_PUBLIC_TELEGRAM_API_HASH=your32characterapihashgoeshere';

  async function copy(text: string, key: string) {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(key);
      setTimeout(() => setCopied(null), 1600);
    } catch {
      // Clipboard can be blocked; the text is selectable either way.
    }
  }

  return (
    <div className="flex min-h-dvh items-center justify-center bg-bg p-6">
      <div className="w-full max-w-lg">
        <div className="mb-5 flex items-start gap-3">
          <div className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-accent-soft text-accent">
            <Icon.Key size={22} />
          </div>
          <div>
            <h1 className="text-lg font-semibold tracking-tight">{strings.setupTitle}</h1>
            <p className="mt-1 text-xs leading-relaxed text-text-secondary">
              {strings.setupBody} They stay in your browser — Nodogram has no server.
            </p>
          </div>
        </div>

        <ol className="flex flex-col gap-3 border-t border-border pt-5">
          <Step n={1}>
            Sign in at{' '}
            <a
              href="https://my.telegram.org"
              target="_blank"
              rel="noreferrer noopener"
              className="text-accent underline underline-offset-2"
            >
              my.telegram.org
            </a>{' '}
            and open <strong>API development tools</strong>.
          </Step>
          <Step n={2}>
            Create an app to get your <strong>api_id</strong> and <strong>api_hash</strong>.
          </Step>
          <Step n={3}>
            Add them to <code className="rounded bg-bg-elevated px-1 py-0.5 text-[11px]">.env.local</code>{' '}
            locally, or in <strong>Vercel → Settings → Environment Variables</strong>:
          </Step>
        </ol>

        <div className="mt-3 flex items-start justify-between gap-2 rounded-lg border border-border bg-bg-elevated p-3">
          <pre className="overflow-x-auto font-mono text-[11px] leading-relaxed text-text-secondary">
            {snippet}
          </pre>
          <button
            onClick={() => copy(snippet, 'env')}
            className="shrink-0 rounded px-2 py-1 text-[11px] text-text-secondary hover:bg-bg-hover"
          >
            {copied === 'env' ? 'Copied' : 'Copy'}
          </button>
        </div>

        {detail && (
          <p className="mt-3 rounded-lg border border-border bg-bg-elevated p-2.5 font-mono text-[10px] leading-relaxed text-text-secondary">
            {detail}
          </p>
        )}

        <p className="mt-5 text-[10px] leading-relaxed text-text-tertiary">
          Note: in any browser-based Telegram client these values are visible in the
          page source. That is unavoidable and is how Telegram&apos;s own web client works,
          but it means the credentials are public.
        </p>

        <p className="mt-3 text-[10px] leading-relaxed text-text-tertiary">
          {strings.unofficial}
        </p>
      </div>
    </div>
  );
}

function Step({ n, children }: { n: number; children: React.ReactNode }) {
  return (
    <li className="flex items-start gap-2.5">
      <span className="mt-px flex size-4.5 shrink-0 items-center justify-center rounded-full bg-accent-soft text-[10px] font-semibold text-accent">
        {n}
      </span>
      <span className="text-xs leading-relaxed text-text">{children}</span>
    </li>
  );
}
