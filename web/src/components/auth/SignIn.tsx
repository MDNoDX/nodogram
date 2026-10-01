'use client';

/**
 * Sign-in, following the steps Telegram actually drives:
 * phone → code → (two-step password, if enabled).
 */

import { useState, type FormEvent } from 'react';
import type { AuthState } from '@/lib/domain/types';
import { strings } from '@/lib/i18n/strings';
import { Icon } from '@/components/ui/Icons';

export function SignIn({
  state,
  error,
  detail,
  busy,
  onPhone,
  onCode,
  onPassword,
}: {
  state: AuthState;
  error?: string;
  detail?: string;
  busy: boolean;
  onPhone: (value: string) => void;
  onCode: (value: string) => void;
  onPassword: (value: string) => void;
}) {
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [password, setPassword] = useState('');
  const [showDetail, setShowDetail] = useState(false);

  function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    if (state.kind === 'phone') onPhone(phone.trim());
    else if (state.kind === 'code') onCode(code.trim());
    else if (state.kind === 'password') onPassword(password);
  }

  return (
    <div className="flex min-h-dvh items-center justify-center bg-bg p-6">
      <div className="w-full max-w-sm">
        <div className="mb-7 flex flex-col items-start gap-3">
          <div className="flex size-11 items-center justify-center rounded-xl bg-accent-soft text-accent">
            <Icon.Logo size={24} />
          </div>
          <div>
            <h1 className="text-lg font-semibold tracking-tight">Nodogram</h1>
            <p className="mt-0.5 text-xs text-text-secondary">{strings.signIn}</p>
          </div>
        </div>

        <form onSubmit={submit} className="flex flex-col gap-3">
          {state.kind === 'phone' && (
            <Field
              label={strings.phoneNumber}
              hint={strings.phoneHint}
              value={phone}
              onChange={setPhone}
              type="tel"
              placeholder="+998 90 123 45 67"
              autoFocus
            />
          )}

          {state.kind === 'code' && (
            <Field
              label={strings.verificationCode}
              hint={strings.codeHint}
              value={code}
              onChange={setCode}
              inputMode="numeric"
              placeholder="12345"
              autoFocus
            />
          )}

          {state.kind === 'password' && (
            <Field
              label={strings.twoStepPassword}
              hint={state.hint ? `${strings.passwordHint}: ${state.hint}` : undefined}
              value={password}
              onChange={setPassword}
              type="password"
              autoFocus
            />
          )}

          {error && (
            <div className="rounded-lg border border-danger/30 bg-danger/8 p-2.5">
              <p className="flex items-start gap-1.5 text-xs text-danger">
                <Icon.Warning size={13} />
                <span>{error}</span>
              </p>
              {detail && (
                <>
                  <button
                    type="button"
                    onClick={() => setShowDetail((v) => !v)}
                    className="mt-1.5 text-[11px] text-text-secondary underline underline-offset-2"
                  >
                    {showDetail ? 'Hide details' : 'Details'}
                  </button>
                  {showDetail && (
                    <pre className="mt-1.5 overflow-x-auto rounded bg-bg-elevated p-2 font-mono text-[10px] text-text-secondary">
                      {detail}
                    </pre>
                  )}
                </>
              )}
            </div>
          )}

          <button
            type="submit"
            disabled={busy}
            className="mt-1 flex h-9 items-center justify-center rounded-lg bg-accent text-sm font-medium text-accent-contrast transition-colors hover:bg-accent-hover disabled:opacity-50"
          >
            {busy
              ? 'Working…'
              : state.kind === 'phone'
                ? strings.sendCode
                : state.kind === 'code'
                  ? strings.verify
                  : strings.unlock}
          </button>
        </form>

        <p className="mt-6 text-[10px] leading-relaxed text-text-tertiary">
          {strings.unofficial}
        </p>
      </div>
    </div>
  );
}

function Field({
  label,
  hint,
  value,
  onChange,
  ...rest
}: {
  label: string;
  hint?: string;
  value: string;
  onChange: (value: string) => void;
} & Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'>) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-xs font-medium text-text-secondary">{label}</span>
      <input
        {...rest}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="h-9 rounded-lg border border-border bg-bg-elevated px-3 text-sm text-text outline-none transition-colors focus:border-accent"
      />
      {hint && <span className="text-[11px] leading-relaxed text-text-tertiary">{hint}</span>}
    </label>
  );
}
