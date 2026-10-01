'use client';

/**
 * Nodogram Web — application shell.
 *
 * Everything runs in the browser: MTProto via GramJS, storage via IndexedDB.
 * There is no Nodogram server, which is what keeps message content, drafts and
 * notes private to this device.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import type { TelegramClient } from 'telegram';
import type {
  AuthState,
  Chat,
  ConnectionState,
  Message,
  SidebarDestination,
} from '@/lib/domain/types';
import {
  clearSessionString,
  connect,
  describeError,
  readCredentials,
  saveSessionString,
} from '@/lib/telegram/client';
import {
  UpdateQueue,
  applyDeletedMessages,
  applyIncomingMessage,
  fetchChats,
  fetchMessages,
  loadCachedChats,
  loadCachedMessages,
  markChatRead,
  sendMessage,
} from '@/lib/telegram/sync';
import { loadAllDrafts } from '@/lib/storage/drafts';
import { SetupNotice } from '@/components/auth/SetupNotice';
import { SignIn } from '@/components/auth/SignIn';
import { Sidebar } from '@/components/Sidebar';
import { ChatList } from '@/components/ChatList';
import { Conversation } from '@/components/Conversation';
import { Composer } from '@/components/Composer';

/* eslint-disable @typescript-eslint/no-explicit-any */

export default function Home() {
  const [auth, setAuth] = useState<AuthState>({ kind: 'loading' });
  const [error, setError] = useState<string | undefined>();
  const [detail, setDetail] = useState<string | undefined>();
  const [busy, setBusy] = useState(false);

  // Seeded from the browser's own connectivity flag, so an offline load renders
  // correctly on the first paint instead of flashing "connecting".
  const [connection, setConnection] = useState<ConnectionState>(() =>
    typeof navigator !== 'undefined' && !navigator.onLine ? 'offline' : 'connecting',
  );
  const [chats, setChats] = useState<Chat[]>([]);
  const [messages, setMessages] = useState<Message[]>([]);
  const [selectedChatId, setSelectedChatId] = useState<string | undefined>();
  const [destination, setDestination] = useState<SidebarDestination>('allChats');
  const [search, setSearch] = useState('');
  const [chatsLoading, setChatsLoading] = useState(true);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [draftChatIds, setDraftChatIds] = useState<Set<string>>(new Set());

  const clientRef = useRef<TelegramClient | null>(null);
  const phoneRef = useRef('');
  const codeHashRef = useRef('');
  const queueRef = useRef(new UpdateQueue());

  // ── Startup ───────────────────────────────────────────────────────────────

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const credentials = readCredentials();
      if (!credentials.ok) {
        setAuth({ kind: 'needsCredentials', detail: credentials.detail });
        return;
      }

      // Paint from cache first: the UI should never sit empty while the network
      // is still waking up.
      const cached = await loadCachedChats();
      if (!cancelled && cached.length > 0) {
        setChats(cached);
        setChatsLoading(false);
      }
      void refreshDraftIndicators();

      try {
        const { client, isAuthorized } = await connect(credentials.credentials);
        if (cancelled) return;

        clientRef.current = client;
        setConnection('connected');

        if (isAuthorized) {
          setAuth({ kind: 'ready' });
          void loadChats(client);
          attachUpdateHandlers(client);
        } else {
          setAuth({ kind: 'phone' });
        }
      } catch (e) {
        if (cancelled) return;
        const described = describeError(e);
        setError(described.message);
        setDetail(described.detail);
        setConnection('offline');
        setAuth({ kind: 'phone' });
      }
    })();

    return () => {
      cancelled = true;
    };
    // Runs once: the client's own lifecycle is managed imperatively below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Browsers report connectivity directly, which is more reliable than guessing
  // from failed requests.
  useEffect(() => {
    function online() {
      setConnection(clientRef.current ? 'connected' : 'connecting');
    }
    function offline() {
      setConnection('offline');
    }
    window.addEventListener('online', online);
    window.addEventListener('offline', offline);
    return () => {
      window.removeEventListener('online', online);
      window.removeEventListener('offline', offline);
    };
  }, []);

  const refreshDraftIndicators = useCallback(async () => {
    const drafts = await loadAllDrafts();
    setDraftChatIds(new Set(drafts.filter((d) => d.text.trim()).map((d) => d.chatId)));
  }, []);

  // ── Data loading ──────────────────────────────────────────────────────────

  async function loadChats(client: TelegramClient) {
    setChatsLoading(true);
    try {
      setChats(await fetchChats(client));
    } catch (e) {
      const described = describeError(e);
      setError(described.message);
      setDetail(described.detail);
    } finally {
      setChatsLoading(false);
    }
  }

  const openChat = useCallback(async (chatId: string) => {
    setSelectedChatId(chatId);
    setMessages(await loadCachedMessages(chatId));

    const client = clientRef.current;
    if (!client) return;

    setMessagesLoading(true);
    try {
      setMessages(await fetchMessages(client, chatId));
      await markChatRead(client, chatId);
      setChats((current) =>
        current.map((c) => (c.id === chatId ? { ...c, unreadCount: 0 } : c)),
      );
    } catch (e) {
      const described = describeError(e);
      setError(described.message);
      setDetail(described.detail);
    } finally {
      setMessagesLoading(false);
    }
  }, []);

  /**
   * Updates are pushed through a serial queue: Telegram requires they be
   * applied in order, and processing them concurrently corrupts ordering and
   * unread counts.
   */
  function attachUpdateHandlers(client: TelegramClient) {
    client.addEventHandler((update: any) => {
      const type = update?.className ?? '';

      if (type === 'UpdateNewMessage' || type === 'UpdateNewChannelMessage') {
        queueRef.current.enqueue(async () => {
          const message = await applyIncomingMessage(update);
          if (!message) return;
          setChats(await loadCachedChats());
          setMessages((current) =>
            message.chatId === selectedChatIdRef.current &&
            !current.some((m) => m.id === message.id)
              ? [...current, message]
              : current,
          );
        });
      }

      if (type === 'UpdateDeleteMessages' || type === 'UpdateDeleteChannelMessages') {
        queueRef.current.enqueue(async () => {
          const deleted = await applyDeletedMessages(update);
          if (deleted.length === 0) return;
          setMessages((current) => current.filter((m) => !deleted.includes(m.id)));
        });
      }
    });
  }

  // Keeps the update handler reading the current selection without re-binding.
  const selectedChatIdRef = useRef<string | undefined>(undefined);
  selectedChatIdRef.current = selectedChatId;

  // ── Authentication ────────────────────────────────────────────────────────

  async function submitPhone(value: string) {
    const client = clientRef.current;
    if (!client || !value) return;

    setBusy(true);
    setError(undefined);
    try {
      const { Api } = await import('telegram');
      const result: any = await client.invoke(
        new Api.auth.SendCode({
          phoneNumber: value,
          apiId: Number(process.env.NEXT_PUBLIC_TELEGRAM_API_ID),
          apiHash: String(process.env.NEXT_PUBLIC_TELEGRAM_API_HASH),
          settings: new Api.CodeSettings({}),
        }),
      );
      phoneRef.current = value;
      codeHashRef.current = result.phoneCodeHash;
      setAuth({ kind: 'code', phoneNumber: value });
    } catch (e) {
      const described = describeError(e);
      setError(described.message);
      setDetail(described.detail);
    } finally {
      setBusy(false);
    }
  }

  async function submitCode(value: string) {
    const client = clientRef.current;
    if (!client || !value) return;

    setBusy(true);
    setError(undefined);
    try {
      const { Api } = await import('telegram');
      await client.invoke(
        new Api.auth.SignIn({
          phoneNumber: phoneRef.current,
          phoneCodeHash: codeHashRef.current,
          phoneCode: value,
        }),
      );
      await finishSignIn(client);
    } catch (e) {
      const raw = e instanceof Error ? e.message : String(e);
      if (raw.includes('SESSION_PASSWORD_NEEDED')) {
        // Two-step verification: expected, not an error to show in red.
        setAuth({ kind: 'password' });
        setError(undefined);
      } else {
        const described = describeError(e);
        setError(described.message);
        setDetail(described.detail);
      }
    } finally {
      setBusy(false);
    }
  }

  async function submitPassword(value: string) {
    const client = clientRef.current;
    if (!client || !value) return;

    setBusy(true);
    setError(undefined);
    try {
      await client.signInWithPassword(
        {
          apiId: Number(process.env.NEXT_PUBLIC_TELEGRAM_API_ID),
          apiHash: String(process.env.NEXT_PUBLIC_TELEGRAM_API_HASH),
        },
        {
          password: async () => value,
          onError: async (err: Error) => {
            setError(describeError(err).message);
            return true;
          },
        },
      );
      await finishSignIn(client);
    } catch (e) {
      const described = describeError(e);
      setError(described.message);
      setDetail(described.detail);
    } finally {
      setBusy(false);
    }
  }

  async function finishSignIn(client: TelegramClient) {
    saveSessionString(client.session.save() as unknown as string);
    setAuth({ kind: 'ready' });
    setError(undefined);
    attachUpdateHandlers(client);
    await loadChats(client);
  }

  async function sendCurrentMessage(text: string) {
    const client = clientRef.current;
    if (!client || !selectedChatId) return;

    // Optimistic insert, clearly marked as sending — the UI must not imply the
    // message has been delivered before the server confirms it.
    const optimistic: Message = {
      id: `pending-${Date.now()}`,
      chatId: selectedChatId,
      senderName: '',
      text,
      date: new Date(),
      isOutgoing: true,
      hasAttachment: false,
      sendState: { kind: 'sending' },
    };
    setMessages((current) => [...current, optimistic]);

    try {
      const sent = await sendMessage(client, selectedChatId, text);
      setMessages((current) =>
        current.map((m) => (m.id === optimistic.id ? (sent ?? { ...m, sendState: { kind: 'sent' } }) : m)),
      );
      setChats(await loadCachedChats());
    } catch (e) {
      const described = describeError(e);
      setMessages((current) =>
        current.map((m) =>
          m.id === optimistic.id
            ? { ...m, sendState: { kind: 'failed', reason: described.message } }
            : m,
        ),
      );
    }
  }

  // ── Keyboard ──────────────────────────────────────────────────────────────

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key === 'k') {
        event.preventDefault();
        document.querySelector<HTMLInputElement>('input[aria-label="Search conversations"]')?.focus();
      }
      if (event.key === 'Escape') {
        setSearch('');
      }
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  function signOut() {
    clearSessionString();
    window.location.reload();
  }

  // ── Render ────────────────────────────────────────────────────────────────

  if (auth.kind === 'needsCredentials') return <SetupNotice detail={auth.detail} />;

  if (auth.kind === 'loading') {
    return (
      <div className="flex min-h-dvh items-center justify-center bg-bg">
        <div className="size-5 animate-spin rounded-full border-2 border-border border-t-accent" />
      </div>
    );
  }

  if (auth.kind !== 'ready') {
    return (
      <SignIn
        state={auth}
        error={error}
        detail={detail}
        busy={busy}
        onPhone={submitPhone}
        onCode={submitCode}
        onPassword={submitPassword}
      />
    );
  }

  const selectedChat = chats.find((c) => c.id === selectedChatId);
  const unreadTotal = chats.reduce((sum, c) => sum + (c.isMuted ? 0 : c.unreadCount), 0);

  return (
    <div className="flex h-dvh overflow-hidden bg-bg text-text">
      <Sidebar
        selected={destination}
        onSelect={setDestination}
        connectionState={connection}
        unreadTotal={unreadTotal}
        draftCount={draftChatIds.size}
      />

      <ChatList
        chats={chats}
        destination={destination}
        selectedChatId={selectedChatId}
        onSelect={openChat}
        search={search}
        onSearch={setSearch}
        loading={chatsLoading}
        draftChatIds={draftChatIds}
      />

      <main className="flex min-w-0 flex-1 flex-col">
        <Conversation chat={selectedChat} messages={messages} loading={messagesLoading} />

        {selectedChat && (
          <Composer
            chatId={selectedChat.id}
            onSend={sendCurrentMessage}
            disabled={connection === 'offline'}
            onDraftChange={(chatId, hasText) => {
              setDraftChatIds((current) => {
                const next = new Set(current);
                if (hasText) next.add(chatId);
                else next.delete(chatId);
                return next;
              });
            }}
          />
        )}

        {error && (
          <div className="flex items-center justify-between gap-3 border-t border-danger/30 bg-danger/8 px-4 py-2">
            <span className="text-xs text-danger">{error}</span>
            <button
              onClick={() => setError(undefined)}
              className="text-[11px] text-text-secondary hover:underline"
            >
              Dismiss
            </button>
          </div>
        )}
      </main>

      <button
        onClick={signOut}
        className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:right-2 focus:rounded focus:bg-bg-elevated focus:px-2 focus:py-1 focus:text-xs"
      >
        Sign out
      </button>
    </div>
  );
}
