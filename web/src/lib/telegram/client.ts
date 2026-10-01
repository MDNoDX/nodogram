/**
 * The single point in Nodogram Web that touches MTProto.
 *
 * Counterpart of the macOS app's TelegramGateway: protocol types stop here and
 * at mapping.ts, so the rest of the app only ever sees domain objects
 * (Documentation/ARCHITECTURE.md §2).
 *
 * Browser specifics that shaped this file:
 *   - GramJS connects over WebSocket in the browser, not raw TCP.
 *   - The session string is persisted in localStorage, which is what lets a
 *     reload skip re-authentication. It is a credential: see SECURITY note.
 *   - api_id/api_hash are compiled into the bundle and are therefore public.
 *     Unavoidable for any browser Telegram client; recorded in DECISIONS.md D8.
 */

import type { TelegramClient as TelegramClientType } from 'telegram';
import type { StringSession as StringSessionType } from 'telegram/sessions';

/**
 * SECURITY: this key holds a Telegram session string, which grants access to
 * the account. It lives in localStorage because a browser client has nowhere
 * better; signing out must therefore delete it, not merely forget it in memory.
 */
const SESSION_STORAGE_KEY = 'nodogram.session';

export interface Credentials {
  apiId: number;
  apiHash: string;
}

export type CredentialsResult =
  | { ok: true; credentials: Credentials }
  | { ok: false; detail: string };

/**
 * Reads credentials from the build-time environment.
 *
 * Returns a precise explanation rather than a bare failure, because the most
 * common first-run problem is simply that these were never set.
 */
export function readCredentials(): CredentialsResult {
  const rawId = process.env.NEXT_PUBLIC_TELEGRAM_API_ID?.trim() ?? '';
  const rawHash = process.env.NEXT_PUBLIC_TELEGRAM_API_HASH?.trim() ?? '';

  if (!rawId || !rawHash) {
    return {
      ok: false,
      detail:
        'NEXT_PUBLIC_TELEGRAM_API_ID and NEXT_PUBLIC_TELEGRAM_API_HASH are not set. ' +
        'Add them in .env.local for local development, or in Vercel → Settings → Environment Variables.',
    };
  }

  const apiId = Number.parseInt(rawId, 10);
  if (!Number.isFinite(apiId) || apiId <= 0) {
    return { ok: false, detail: `NEXT_PUBLIC_TELEGRAM_API_ID must be a number, but was "${rawId}".` };
  }
  if (rawHash.length !== 32) {
    return {
      ok: false,
      detail: `NEXT_PUBLIC_TELEGRAM_API_HASH should be 32 characters, but was ${rawHash.length}.`,
    };
  }

  return { ok: true, credentials: { apiId, apiHash: rawHash } };
}

export function loadSessionString(): string {
  if (typeof window === 'undefined') return '';
  try {
    return window.localStorage.getItem(SESSION_STORAGE_KEY) ?? '';
  } catch {
    // Private windows and blocked site data both throw here. An empty session
    // just means the user signs in again, so this must not be fatal.
    return '';
  }
}

export function saveSessionString(session: string): void {
  try {
    window.localStorage.setItem(SESSION_STORAGE_KEY, session);
  } catch {
    // Non-fatal: the session simply will not survive a reload.
  }
}

export function clearSessionString(): void {
  try {
    window.localStorage.removeItem(SESSION_STORAGE_KEY);
  } catch {
    /* nothing useful to do */
  }
}

/** Lazily imported so GramJS never ends up in the server bundle. */
async function gramjs() {
  const [{ TelegramClient }, { StringSession }, { Logger, LogLevel }] = await Promise.all([
    import('telegram'),
    import('telegram/sessions'),
    import('telegram/extensions/Logger'),
  ]);
  return { TelegramClient, StringSession, Logger, LogLevel };
}

export interface ConnectResult {
  client: TelegramClientType;
  session: StringSessionType;
  isAuthorized: boolean;
}

/**
 * Creates and connects a client, reusing any stored session.
 *
 * `connect()` is deliberately separate from authorisation: a stored session
 * usually means we come back already authorised, and asking the user to sign in
 * again when they do not need to would be the single most annoying bug here.
 */
export async function connect(credentials: Credentials): Promise<ConnectResult> {
  const { TelegramClient, StringSession, Logger, LogLevel } = await gramjs();
  const session = new StringSession(loadSessionString());

  // GramJS logs connection detail to the console by default, including server
  // names and protocol internals. That is noise for users and leaks more than
  // it should, so only genuine errors are surfaced.
  const logger = new Logger(LogLevel.ERROR);

  const client = new TelegramClient(session, credentials.apiId, credentials.apiHash, {
    connectionRetries: 5,
    // Browsers cannot open raw TCP, so GramJS tunnels MTProto over WebSocket.
    useWSS: true,
    baseLogger: logger,
  });

  await client.connect();
  const isAuthorized = await client.isUserAuthorized();

  if (isAuthorized) {
    saveSessionString(session.save() as unknown as string);
  }

  return { client, session, isAuthorized };
}

/**
 * Translates a protocol error into copy a person can act on.
 *
 * Raw MTProto errors are shouty constants (PHONE_CODE_INVALID), which must
 * never reach the UI. The original is preserved for a "Details" disclosure.
 */
export function describeError(error: unknown): { message: string; detail?: string } {
  const raw = error instanceof Error ? error.message : String(error);

  if (raw.includes('PHONE_NUMBER_INVALID')) {
    return { message: "That phone number doesn't look right. Include your country code.", detail: raw };
  }
  if (raw.includes('PHONE_CODE_INVALID')) {
    return { message: "That code wasn't accepted. Check it and try again.", detail: raw };
  }
  if (raw.includes('PHONE_CODE_EXPIRED')) {
    return { message: 'That code expired. Request a new one.', detail: raw };
  }
  if (raw.includes('PASSWORD_HASH_INVALID')) {
    return { message: "That password wasn't accepted.", detail: raw };
  }
  if (raw.includes('SESSION_PASSWORD_NEEDED')) {
    return { message: 'This account has two-step verification enabled.', detail: raw };
  }
  if (raw.includes('FLOOD_WAIT')) {
    const seconds = raw.match(/\d+/)?.[0] ?? '60';
    return { message: `Telegram asked us to slow down. Try again in ${seconds}s.`, detail: raw };
  }
  if (raw.includes('AUTH_KEY_UNREGISTERED') || raw.includes('SESSION_REVOKED')) {
    return { message: 'You were signed out. Sign in again to continue.', detail: raw };
  }
  if (raw.toLowerCase().includes('network') || raw.toLowerCase().includes('disconnect')) {
    return { message: "You're offline. Nodogram will reconnect automatically.", detail: raw };
  }

  return { message: "Telegram couldn't complete that request.", detail: raw };
}
