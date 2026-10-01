# Nodogram — Architecture

**Phase 1 deliverable.** Every technical claim below was verified on
2026-10-01 against upstream sources or by building and running code on the
target machine. Findings from that verification are marked **[verified]**.

---

## 1. Verification record

Before designing anything, the foundation was tested rather than assumed.

### 1.1 Toolchain **[verified]**

| | |
|---|---|
| Hardware | Apple M1 Pro (`arm64`) |
| macOS | 26.5.2 (build 25F84) |
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 |
| SDK | macOS 26.5 |

### 1.2 TDLib runs correctly here **[verified]**

A probe was built against `TDLibKit` and executed. Real output:

```
Create Td with layer 229, database version 14 and version 61 on 4 threads
updateOption { name = "version"     value = "1.8.67" }
updateOption { name = "commit_hash" value = "42e6a5259551178d1dab54a22ad96d14bd906e20" }
updateAuthorizationState { authorizationStateWaitTdlibParameters {} }
```

This establishes three facts that shape the design:

1. **TDLib 1.8.67, MTProto layer 229** runs natively on Apple Silicon.
2. The TDLib commit reported at runtime is
   `42e6a5259551178d1dab54a22ad96d14bd906e20`. This is **not** the suffix of
   the `TDLibFramework` version (`1.8.67-0efabf93`) — that suffix identifies
   TDLibFramework's own build, not the TDLib commit it packages. Only running
   the probe establishes which TDLib you actually have.
3. **TDLib is dual-natured: it pushes updates *and* answers requests.**
   `version` and `commit_hash` arrive unsolicited as `updateOption` pushes, and
   the same values can also be fetched with `getOption` — which answers
   immediately, before any login.

### The initialization boundary, measured exactly

`setTdlibParameters` gates *account* functionality, not the whole client. This
was characterized rather than assumed **[verified]**:

| Request, before `setTdlibParameters` | Result |
|---|---|
| `getOption("version")` | succeeds → `"1.8.67"` |
| `getOption("commit_hash")` | succeeds → `"42e6a525…"` |
| `getMe()` | `Error(code: 400, message: "Initialization parameters are needed: call setTdlibParameters first")` |

> **Design consequence.** TDLib **fails fast with a typed error** rather than
> hanging, so modelling requests as ordinary `async` calls is sound. The gateway
> must still (a) send `setTdlibParameters` before any account request, and
> (b) treat error 400 as a recoverable "not initialized yet" rather than a
> failure to surface to the user. Updates and requests are *both* first-class:
> the ordered update stream carries state changes (§5), while requests are plain
> async calls over the same client.

A correction worth recording: an earlier draft of this document claimed
`getOption` hung before initialization and that the gateway therefore had to be
purely update-driven. That was wrong — the apparent hang was a stale binary
masking a build failure (`@main` is illegal in a file named `main.swift`). The
table above is the measured behaviour. `Tools/tdlib-probe` now exercises it on
every dependency bump so the claim stays honest.

### 1.3 Swift 6 concurrency conflict, and its resolution **[verified]**

`TDLibKit.TDLibClient` is **not `Sendable`** (the package is
`swift-tools-version:5.3`). Under Swift 6 strict concurrency, touching it from an
actor fails to compile:

```
error: sending value of non-Sendable type 'TDLibClient' risks causing data races
  note: sending main actor-isolated value ... to nonisolated instance method
```

Wrapping it in an `actor` **does not** fix this, because TDLibKit's methods are
`nonisolated async` — calling one *sends* the client out of the actor's domain.

The resolution is grounded in TDLib's own documented C contract
(`td/telegram/td_json_client.h`) **[verified, quoted]**:

- *"share the client_id with other threads, which will be able to send requests
  via `td_send`"* → **send is thread-safe.**
- *"This function [`td_receive`] must not be called simultaneously from two
  different threads."* → **exactly one receiver.**
- *"all updates and responses to requests must be applied in the order they were
  received for consistency"* → **ordering is a correctness requirement.**
- *"All TDLib client instances must be closed before application termination to
  ensure data consistency."* → **graceful shutdown is mandatory.**

So a `final class … : @unchecked Sendable` that confines the client is *correct*,
not a loophole: we only ever send from arbitrary tasks (thread-safe per contract)
while a single owned task drains receive. This compiled and ran clean under
Swift 6 strict concurrency, and is exercised by `Tools/tdlib-probe` — a
deliberate miniature of the real gateway **[verified: exits 0, reports the
pinned version and commit]**. **`@unchecked Sendable` appears in exactly one
type in the application and carries that citation as a comment.**

Two further traps, both cost real time and are recorded so they are not re-hit:

- An `actor` does **not** solve this. TDLibKit's methods are `nonisolated
  async`, so calling one still *sends* the client out of the actor's domain.
- `@main` is illegal in a file named `main.swift`. Getting this wrong leaves a
  **stale binary** that `swift run` happily executes, which silently masks the
  real build failure — the trap that produced the incorrect claim corrected in
  §1.2.

The third bullet is the most consequential sentence in this document. It forbids
parallel update processing anywhere in the sync layer.

### 1.4 Dependency facts **[verified]**

| Package | Version | License | Note |
|---|---|---|---|
| TDLib | 1.8.67 | BSL-1.0 | via prebuilt xcframework |
| TDLibFramework | `1.8.67-0efabf93` | MIT | ~300 MB binary; links `libc++`, `libz` |
| TDLibKit | `1.5.2-tdlib-1.8.67-0efabf93` | MIT | macOS 10.15+; `TdInt64` wraps int64 |
| GRDB.swift | 7.11.0 | MIT | `swift-tools-version:6.1`; FTS5 on by default |

Two practical traps found:

- **TDLibKit version ranges do not work.** Tags are SemVer *prereleases*
  (`1.5.2-tdlib-1.8.67-0efabf93`), so `from: "1.8.67"` fails to resolve
  **[verified: resolution error]**. `exact:` is mandatory. Recorded in `UPSTREAM.md`.
- **int64 is `TdInt64`, not `Int64`** — TDLib JSON-encodes 64-bit integers as
  strings. The mapping layer converts at the boundary **[verified: compile error]**.

---

## 2. Layering

The mandated direction of dependency. Each layer knows only the one below.

```
┌──────────────────────────────────────────────────────────┐
│  UI            SwiftUI + AppKit  (Features/*, UI/*)      │
├──────────────────────────────────────────────────────────┤
│  Presentation  @Observable ViewModels, @MainActor        │
├──────────────────────────────────────────────────────────┤
│  Domain        Models, UseCases, Repository protocols    │  ← no TDLib types
├──────────────────────────────────────────────────────────┤
│  Data          Repository impls (Remote + Local merge)   │
├───────────────────────────┬──────────────────────────────┤
│  Synchronization          │  Local Store                 │
│  single ordered consumer  │  GRDB/SQLCipher + FTS5       │
├───────────────────────────┼──────────────────────────────┤
│  Telegram Gateway         │  (local-only data never      │
│  TDLib confinement        │   leaves this column)        │
└───────────────────────────┴──────────────────────────────┘
```

**The hard rule (brief §79, §49).** No `TDLibKit` type ever appears above the
Gateway/Mapping boundary. `Nodogram/Domain` must compile with TDLibKit removed
from the package graph — this is enforced as a build-time check, not a
convention, because it is the one rule that keeps upstream TDLib churn from
reaching our features.

### Why this specific split

The brief demands both "incorporate future Telegram upstream changes" and
"don't destroy our custom functionality." Those pull in opposite directions
unless local-only state is *physically* unable to reach the protocol layer. That
is why Synchronization and Local Store sit side by side rather than stacked: the
right column has no dependency on the left, so a TDLib upgrade cannot schema-break
drafts, notes, or the archive.

---

## 3. Remote vs local data (brief §50 — mandatory)

TDLib owns its **own** encrypted database for remote data. We do not duplicate
it; re-storing messages would mean two sources of truth and guaranteed drift.

| REMOTE — TDLib's store, authoritative | LOCAL — our GRDB store, ours alone |
|---|---|
| account, chats, messages, media | draft history, local notes |
| server read state, reactions | bookmarks, collections, tags |
| edit/delete notifications | deletion archive + events |
| message content | local unread overrides |
| | local read events, FTS index of local-only data |

Local rows reference remote objects by `(account_id, chat_id, message_id)` and
**never** embed remote content except where the user explicitly opted into
retention (the archive, §6). That keeps "clear cache" from destroying user-authored
data, and keeps the archive the only place where retained remote content lives —
one feature to encrypt, audit and erase, rather than a diffuse leak.

---

## 4. Telegram Gateway

`Nodogram/Telegram/Gateway` — the only code aware TDLib exists.

```swift
/// The single confinement point for TDLib.
///
/// `@unchecked Sendable` is justified by td_json_client.h: `td_send` is callable
/// from any thread; `td_receive` has exactly one owner (`receiveLoop`).
final class TelegramGateway: @unchecked Sendable {
    private let manager: TDLibClientManager
    private let client: TDLibClient
    private let updates: AsyncStream<TDUpdate>   // ordered, never parallel
}
```

Responsibilities, and nothing else:

1. Own the client lifecycle: send `setTdlibParameters` before any account
   request (§1.2), and `close()` before termination (§1.3).
2. Expose **one** ordered `AsyncStream` of updates.
3. Correlate requests to responses. TDLibKit already does this via TDLib's
   `@extra` field, so the gateway consumes that rather than reimplementing it.
4. Translate TDLib errors into domain errors.

It performs no business logic, no persistence, and no UI work.

### Authorization is a state machine, not a form

TDLib drives login by emitting `updateAuthorizationState`. We mirror its states
rather than inventing our own flow, because any divergence desynchronises login:
`WaitTdlibParameters → WaitPhoneNumber → WaitCode → WaitPassword(2FA) →
WaitRegistration → Ready → LoggingOut → Closed`.

---

## 5. Synchronization

**One** task consumes the update stream, in receive order (§1.3). Per update:

```
receive → map to domain → write LOCAL txn (if any) → commit
        → publish UI delta → enqueue async FTS index
```

Ordering, commit-before-publish, and async indexing are each required: the first
by TDLib's contract, the second so UI can never render uncommitted state (brief
§47), the third so indexing cannot block the UI (brief §51).

### Edge cases this design absorbs (brief §78)

| Case | Handling |
|---|---|
| Duplicate update | Idempotent upserts keyed on `(account, chat, message)` |
| Out-of-order delivery | Impossible by construction — single ordered consumer |
| Remote edit | `updateMessageContent` → append `MessageRevision`, keep prior |
| Remote delete | `updateDeleteMessages` → write `DeletionEvent`; archive if opted in |
| Network loss mid-send | Message stays `OFFLINE_PENDING`; TDLib resends on reconnect |
| Disk full | Writes are transactional; failure surfaces as a retryable error |
| Clock change | Store server timestamps verbatim; never derive from local clock |
| Account switch mid-upload | Per-account gateway; uploads bound to that account's queue |
| Sleep / wake | Flush drafts on `NSWorkspace.willSleepNotification` |

---

## 6. The four differentiating subsystems

These are the features Telegram lacks. Each is local-only by construction.

### 6.1 Drafts (brief §10, §11, §23)

TDLib's own draft is thin **[verified from `td_api.tl`]**:

```
draftMessage reply_to:InputMessageReplyTo date:int32
             content:DraftMessageContent effect_id:int64 … = DraftMessage;
```

It carries reply target, date and content — but **no cursor position, no
selection range, no attachment staging, and no history**. So the brief's draft
engine is not reinventing a wheel; the wheel does not exist. We keep both:

- **`setChatDraftMessage`** → syncs the text to other Telegram devices.
- **Local `Draft`** → cursor, selection, attachment staging, composer state.
- **Local `DraftRevision`** → the history, with retention policy.

Durability: debounced autosave (~400 ms idle), plus forced flush on chat switch,
window close, sleep, and termination. Each save is a single transaction, so a
crash yields either the old draft or the new one — never a torn one.

### 6.2 Read-time metadata (brief §9, §66)

The brief says *"Do NOT invent read timestamps."* TDLib gives us the exact
vocabulary to obey that **[verified from `td_api.tl`]**:

```
messageReadDateRead read_date:int32        = MessageReadDate;
messageReadDateUnread                      = MessageReadDate;
messageReadDateTooOld                      = MessageReadDate;
messageReadDateUserPrivacyRestricted       = MessageReadDate;
messageReadDateMyPrivacyRestricted         = MessageReadDate;
```

This maps 1:1 onto a domain enum, and **every** case gets honest UI copy —
including "the server no longer knows" and "you hid yours, so you can't see
theirs" (a reciprocity rule we must *explain*, not silently swallow):

| TDLib case | UI |
|---|---|
| `…Read(read_date)` | "Read at 14:32" (exact, server-confirmed) |
| `…Unread` | "Delivered" |
| `…TooOld` | "Read · time no longer available" |
| `…UserPrivacyRestricted` | "Read · time hidden by recipient" |
| `…MyPrivacyRestricted` | "Read · enable your read times to see theirs" |

Groups use `getMessageViewers → messageViewer user_id view_date`, giving a true
"Read by" list with per-user times. Server-confirmed values are stored in
columns distinct from our local read events, so the two can never be conflated
(brief §8).

### 6.3 Local archive of deleted messages (brief §12, §13, §68, §69)

On `updateDeleteMessages` we always write a `DeletionEvent` (metadata only). We
retain *content* only if the user explicitly enabled retention for that scope.

**The honesty requirement is a feature, not a disclaimer.** The settings screen
states plainly: this preserves only what this Mac already received; it does not
defeat server-side deletion and cannot recover a message the client never saw.
"Forever" requires explicit confirmation. The archive is encrypted (§7) and
erasable in one action. We never reinsert archived content into the live chat.

### 6.4 Search (brief §18, §51)

Two engines, deliberately not merged:

- **Remote** — TDLib `searchChatMessages` / `searchMessages` for server history.
- **Local** — SQLite **FTS5** (GRDB enables it by default **[verified]**) over
  local-only data: drafts, revisions, notes, bookmarks, archive.

A unified query planner parses `from: in: before: after: during: has: type: tag: is:`,
dispatches each clause to whichever engine can answer it, and merges results.
Local results are instant and offline; remote clauses degrade gracefully when
offline rather than failing the whole query.

---

## 7. Security (summary — see `SECURITY_MODEL.md`)

- TDLib's database encrypted with a key held in **Keychain**, passed via
  `setTdlibParameters(database_encryption_key:)`.
- Our GRDB database encrypted with **SQLCipher**, separate Keychain-held key.
- **Per-account isolation:** separate directories, databases, and keys (brief §40).
- App lock (password / Touch ID) gates key release.
- **No custom cryptography.** TDLib's reviewed MTProto + SQLCipher + Keychain only.
- No telemetry. Message content, drafts, notes and archives are never transmitted
  anywhere except to Telegram as the protocol requires.

---

## 8. Technology stack

| Concern | Choice | Why |
|---|---|---|
| Language | Swift 6.3, strict concurrency | Compiler-checked data-race safety |
| UI | SwiftUI + AppKit where needed | SwiftUI for composition; AppKit for the list and text views where control matters |
| Protocol | TDLib 1.8.67 via TDLibKit | Official, reviewed, maintained; brief §49 |
| Local DB | GRDB 7.11 + SQLCipher | Migrations, FTS5, Swift 6 native |
| Search | SQLite FTS5 | In-process, no daemon |
| Secrets | Keychain + xcconfig | Never in git |
| Tests | Swift Testing + XCTest | Swift Testing for units; XCTest for UI |

### Where SwiftUI is *not* used, and why

A 100,000-message conversation at 60 FPS (brief §7, §52) is the hardest
constraint in the brief. SwiftUI's `List` does not give sufficient control over
cell reuse and heterogeneous, variable-height content at that scale. The message
list and the composer's text view are therefore **AppKit**
(`NSTableView`/`NSTextView`) behind `NSViewRepresentable`, with SwiftUI
everywhere else. This is a deliberate, measured exception — Phase 15 benchmarks
it rather than trusting the assumption.

---

## 9. Project layout

```
Nodogram/
  App/              entry point, menus, window & scene management
  Features/         one folder per feature; View + ViewModel only
  Domain/           Models, UseCases, Repository protocols   (no TDLib)
  Core/             Database, Security, Search, Synchronization, Concurrency
  Telegram/         Gateway/ + Mapping/   ← the ONLY TDLib-aware code
  UI/               Components, Theme, Accessibility
  Platform/macOS/   notifications, Quick Look, Spotlight, Share, Dock
  Resources/        assets, Localizations/ (en, uz-Latn, uz-Cyrl, ru)
Tests/              Unit, Integration, UITests
Documentation/      this file and its siblings
Config/             xcconfig; Secrets.xcconfig is git-ignored
Tools/              build & maintenance scripts
```

---

## 10. Honest limitations

Per brief §81 — stated plainly rather than papered over.

### 10.1 Voice and video calls are out of scope for v1

**[verified from `td_api.tl`]**:

```
callStateReady protocol:callProtocol servers:vector<callServer> config:string
               encryption_key:bytes emojis:vector<string> … = CallState;
```

TDLib performs call **signalling** only. It hands over call servers and an
encryption key, then expects the client to carry the actual audio/video. That
media layer is `tgcalls` + `tg_owt` — a full WebRTC fork, a very large native
dependency, and a significant audit surface.

The brief lists "Start call" in the command palette and a call sound. Delivering
real calls means adopting that stack; claiming calls without it would be exactly
the fake implementation §81 forbids. **Recommendation:** ship v1 without calls
and surface them honestly (the palette entry offers to open the official app).
Revisit as a dedicated phase. Tell me if you want calls promoted into scope — it
is a phase of its own, not a checkbox.

### 10.2 Other constraints

| Area | Reality |
|---|---|
| Read times | Only as good as `MessageReadDate` allows; `TooOld`/`PrivacyRestricted` are real outcomes shown honestly (§6.2) |
| "Read by" | Limited by Telegram to small groups and recent messages |
| Archive | Preserves only what this device received. Cannot defeat server deletion. Stated in-app (§6.3) |
| Edit history | Only revisions this client actually observed while running |
| Read receipts privacy | Telegram enforces reciprocity — hiding yours hides theirs. Explained, not faked |
| Spotlight | Indexes local-only data (notes, bookmarks, drafts). Indexing message bodies is opt-in, off by default — it would copy plaintext into a system index outside our encryption |
| TDLibKit | Swift 5-era, non-`Sendable`; contained by §1.3. A TDLib upgrade can change generated APIs — `UPSTREAM.md` tracks this |
| Binary size | ~300 MB xcframework download at build time; thinned per-arch when shipped |

---

## 11. Development phases

Gate after each: build clean, tests pass, no known compiler errors, docs updated.

| # | Phase | Exit criterion |
|---|---|---|
| 1 | Analysis & architecture | **← you are here.** These four documents approved |
| 2 | Build environment | Xcode project builds; secrets wired; CI green |
| 3 | Gateway + auth | Real login to a real account; auth state machine covered by tests |
| 4 | Local database | Schema, migrations, per-account isolation, encryption |
| 5 | Chat list | Incremental updates, no full reloads |
| 6 | Conversation UI | Virtualized list, 60 FPS on a synthetic 100k-message chat |
| 7 | Sync hardening | Duplicates, ordering, offline, edge cases from §5 |
| 8 | Composer + drafts | State machine; survives crash, sleep, restart |
| 9 | Draft history | Revisions, restore, compare, retention |
| 10 | Read-time metadata | All five `MessageReadDate` cases rendered honestly |
| 11 | Local archive | Deletion events, retention scopes, warnings, encryption |
| 12 | Bookmarks & notes | Collections, tags, local notes |
| 13 | Search | FTS5 + operators + remote merge |
| 14 | Media & files | Viewer, resumable downloads, Quick Look |
| 15 | Command palette & keyboard | ⌘K, ⌘⇧P, customizable shortcuts |
| 16 | Notifications & focus | Grouping, actions, privacy mode |
| 17 | Security | App lock, Touch ID, Privacy Center, backup |
| 18 | Performance | Diagnostics panel; benchmarks meet §52 targets |
| 19 | Accessibility & localization | VoiceOver; en, uz-Latn, uz-Cyrl, ru |
| 20 | Multi-account & multi-window | Full isolation verified by tests |
| 21 | Export / import | JSON, HTML, Markdown, text; layer-labelled |
| 22 | Testing & audit | Coverage per brief §77 |
| 23 | Packaging | Signed, notarized, hardened runtime |

---

## 12. Top risks

| Risk | Severity | Mitigation |
|---|---|---|
| 100k-message list at 60 FPS | High | AppKit list (§8); benchmark from Phase 6, not Phase 18 |
| TDLibKit non-`Sendable` spreading | High | Single confinement point, already proven (§1.3) |
| TDLib upgrade breaks generated API | Medium | Exact pins + thin mapping layer + `UPSTREAM.md` |
| Archive becomes a privacy liability | High | Encrypted, opt-in, scoped, erasable, explained (§6.3) |
| Scope — the brief is very large | High | Strict phase gates; calls deferred (§10.1) |
| Accidental GPL contamination | High | Hard boundary in `LEGAL_AND_LICENSES.md` §2.2 |
| Local/remote layer confusion | Medium | Domain layer cannot see TDLib; enforced at build time (§2) |

---

*Verified 2026-10-01. Companion documents: `PRODUCT_SPEC.md`,
`SECURITY_MODEL.md`, `LEGAL_AND_LICENSES.md`, `UPSTREAM.md`.*
