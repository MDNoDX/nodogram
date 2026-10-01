# Nodogram — Local Data Model

**Phase 1 deliverable.** Schema for the **local-only** GRDB/SQLCipher database.

> **Critical boundary.** This database stores *local-only* data (`ARCHITECTURE.md`
> §3). Remote chats and messages live in **TDLib's own** database and are **not**
> duplicated here — duplicating them would create two sources of truth and
> guaranteed drift. Rows here reference remote objects by id.
>
> The single exception is `archive_entry.content_encrypted`, which holds retained
> content the user explicitly opted to keep (`SECURITY_MODEL.md` §6). That is the
> *only* place remote message content is stored by us, which is what makes it
> possible to encrypt, audit and erase it as one unit.

---

## 1. Conventions

- Every table carries `account_id` — **per-account isolation** (brief §40).
- Remote references are `(account_id, chat_id, message_id)`; TDLib `int53`/`int64`
  are stored as `INTEGER`. (TDLibKit surfaces these as `TdInt64`; conversion
  happens in the mapping layer — see `ARCHITECTURE.md` §1.4.)
- Timestamps: `INTEGER` Unix seconds. **Server timestamps are stored verbatim**
  and never recomputed from the local clock (brief §78: "user changes Mac clock").
  Locally-generated times are stored in separate `local_*` columns.
- Local primary keys are `TEXT` UUIDs — stable across migrations and sync.
- All writes are transactional; FTS indexing happens **after** commit (brief §51).
- Migrations are append-only and registered in order. **No migration drops or
  rewrites user data** (brief §48).

---

## 2. Entities

### Account

```sql
CREATE TABLE account (
    id                TEXT PRIMARY KEY,          -- local UUID
    telegram_user_id  INTEGER NOT NULL,
    display_name      TEXT    NOT NULL,
    phone_suffix      TEXT,                      -- last digits only, for UI
    tdlib_dir         TEXT    NOT NULL,          -- isolated per account
    created_at        INTEGER NOT NULL,
    last_active_at    INTEGER,
    is_active         INTEGER NOT NULL DEFAULT 1
);
```

Only a phone *suffix* is kept — enough to tell accounts apart, without storing a
full identifier we have no need for.

### Draft and DraftRevision (brief §10, §11)

TDLib's own `draftMessage` carries only `reply_to`, `date`, `content`. Everything
below is what makes the draft engine a differentiator.

```sql
CREATE TABLE draft (
    id                  TEXT PRIMARY KEY,
    account_id          TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    chat_id             INTEGER NOT NULL,
    text                TEXT    NOT NULL DEFAULT '',
    entities_json       TEXT,                      -- formatting
    reply_to_message_id INTEGER,
    reply_quote         TEXT,                      -- inputTextQuote
    forward_context     TEXT,
    cursor_position     INTEGER NOT NULL DEFAULT 0,
    selection_start     INTEGER,
    selection_end       INTEGER,
    composer_state      TEXT    NOT NULL,          -- state-machine state, brief §47
    is_silent           INTEGER NOT NULL DEFAULT 0,
    scheduled_at        INTEGER,
    updated_at          INTEGER NOT NULL,
    synced_to_server_at INTEGER,                   -- NULL = local-only so far
    UNIQUE (account_id, chat_id)
);

CREATE TABLE draft_revision (
    id              TEXT PRIMARY KEY,
    draft_id        TEXT    NOT NULL REFERENCES draft(id) ON DELETE CASCADE,
    account_id      TEXT    NOT NULL,
    chat_id         INTEGER NOT NULL,
    text            TEXT    NOT NULL,
    entities_json   TEXT,
    captured_at     INTEGER NOT NULL,
    capture_reason  TEXT    NOT NULL   -- autosave|chat_switch|quit|sleep|crash_recovery|manual
);
CREATE INDEX idx_draft_revision_lookup ON draft_revision(draft_id, captured_at DESC);
```

`capture_reason` is what makes "Your draft was recovered after an unexpected
shutdown" a truthful statement rather than a guess.

### DraftAttachment

```sql
CREATE TABLE draft_attachment (
    id            TEXT PRIMARY KEY,
    draft_id      TEXT    NOT NULL REFERENCES draft(id) ON DELETE CASCADE,
    local_path    TEXT    NOT NULL,
    original_name TEXT    NOT NULL,
    mime_type     TEXT,
    byte_size     INTEGER,
    content_hash  TEXT,                 -- dedupe, brief §25
    caption       TEXT,
    sort_order    INTEGER NOT NULL DEFAULT 0,
    staged_at     INTEGER NOT NULL,
    is_missing    INTEGER NOT NULL DEFAULT 0   -- brief §78: file vanished locally
);
```

`is_missing` handles the real case where a staged file is deleted or a volume is
unmounted before send: the draft survives and reports the problem instead of
failing opaquely.

### MessageReadState (brief §9) — server vs local, never merged

```sql
CREATE TABLE message_read_state (
    account_id          TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    chat_id             INTEGER NOT NULL,
    message_id          INTEGER NOT NULL,

    -- server-confirmed (from TDLib MessageReadDate); never invented
    read_date_kind      TEXT,     -- read|unread|too_old|user_privacy|my_privacy
    server_read_date    INTEGER,  -- set ONLY when kind = 'read'
    read_date_fetched_at INTEGER,

    -- locally observed; kept strictly separate (brief §8)
    local_first_read_at INTEGER,
    local_last_read_at  INTEGER,
    delivered_at        INTEGER,

    PRIMARY KEY (account_id, chat_id, message_id)
);
```

`read_date_kind` mirrors TDLib's five-case `MessageReadDate` union exactly
(`ARCHITECTURE.md` §6.2). `server_read_date` is `NULL` in the four non-`read`
cases, which is how the schema itself prevents inventing a timestamp.

### MessageViewer — "Read by" for groups

```sql
CREATE TABLE message_viewer (
    account_id  TEXT    NOT NULL,
    chat_id     INTEGER NOT NULL,
    message_id  INTEGER NOT NULL,
    user_id     INTEGER NOT NULL,
    view_date   INTEGER NOT NULL,     -- from messageViewer.view_date
    fetched_at  INTEGER NOT NULL,
    PRIMARY KEY (account_id, chat_id, message_id, user_id)
);
```

### DeletionEvent and ArchiveEntry (brief §12, §13)

Separated on purpose: the **event** (metadata) is always recorded; the
**content** only when the user opted in. So the deletion log stays useful even
with retention off.

```sql
CREATE TABLE deletion_event (
    id                  TEXT PRIMARY KEY,
    account_id          TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    chat_id             INTEGER NOT NULL,
    message_id          INTEGER NOT NULL,
    sender_user_id      INTEGER,
    original_date       INTEGER,            -- server timestamp, verbatim
    detected_at         INTEGER NOT NULL,   -- when WE saw the deletion
    deletion_kind       TEXT,               -- for_all|for_self|unknown
    had_content_retained INTEGER NOT NULL DEFAULT 0,
    UNIQUE (account_id, chat_id, message_id)
);

CREATE TABLE archive_entry (
    id                 TEXT PRIMARY KEY,
    account_id         TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    chat_id            INTEGER NOT NULL,
    message_id         INTEGER NOT NULL,
    sender_user_id     INTEGER,
    original_date      INTEGER NOT NULL,
    archived_at        INTEGER NOT NULL,
    deleted_at         INTEGER,            -- NULL = still present remotely
    content_encrypted  BLOB,               -- archive-key; the ONLY retained remote content
    content_kind       TEXT    NOT NULL,   -- text|photo|video|document|...
    media_local_path   TEXT,
    expires_at         INTEGER,            -- retention policy; NULL = forever
    scope_at_capture   TEXT    NOT NULL,   -- private|group|channel
    UNIQUE (account_id, chat_id, message_id)
);
CREATE INDEX idx_archive_expiry ON archive_entry(expires_at)
    WHERE expires_at IS NOT NULL;
```

`expires_at` drives the scheduled purge; the partial index keeps that sweep cheap.

### MessageRevision (brief §15)

```sql
CREATE TABLE message_revision (
    id            TEXT PRIMARY KEY,
    account_id    TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    chat_id       INTEGER NOT NULL,
    message_id    INTEGER NOT NULL,
    text          TEXT,
    entities_json TEXT,
    observed_at   INTEGER NOT NULL,   -- when THIS client saw this version
    server_edit_date INTEGER,
    revision_index INTEGER NOT NULL
);
CREATE INDEX idx_revision_lookup ON message_revision(account_id, chat_id, message_id, revision_index);
```

Only versions this client actually observed while running — `observed_at` makes
that limitation explicit in the data rather than only in the docs.

### Bookmarks, collections, tags, notes (brief §16, §17)

```sql
CREATE TABLE collection (
    id          TEXT PRIMARY KEY,
    account_id  TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    color       TEXT,
    icon        TEXT,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL
);

CREATE TABLE bookmark (
    id          TEXT PRIMARY KEY,
    account_id  TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    chat_id     INTEGER NOT NULL,
    message_id  INTEGER NOT NULL,
    created_at  INTEGER NOT NULL,
    UNIQUE (account_id, chat_id, message_id)
);

CREATE TABLE bookmark_collection (
    bookmark_id   TEXT NOT NULL REFERENCES bookmark(id) ON DELETE CASCADE,
    collection_id TEXT NOT NULL REFERENCES collection(id) ON DELETE CASCADE,
    PRIMARY KEY (bookmark_id, collection_id)
);

CREATE TABLE tag (
    id         TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    color      TEXT,
    UNIQUE (account_id, name)
);

CREATE TABLE message_tag (
    account_id TEXT    NOT NULL,
    chat_id    INTEGER NOT NULL,
    message_id INTEGER NOT NULL,
    tag_id     TEXT    NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
    PRIMARY KEY (account_id, chat_id, message_id, tag_id)
);

-- Private annotation. MUST NEVER be transmitted (brief §17).
CREATE TABLE local_note (
    id         TEXT PRIMARY KEY,
    account_id TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    chat_id    INTEGER NOT NULL,
    message_id INTEGER,                  -- NULL = chat-level note
    body       TEXT    NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
```

### Local unread override (brief §44)

```sql
CREATE TABLE unread_override (
    account_id          TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    chat_id             INTEGER NOT NULL,
    forced_unread       INTEGER NOT NULL DEFAULT 0,
    unread_from_message_id INTEGER,     -- "mark from here as unread"
    server_last_read_id INTEGER,        -- preserved so server state is NOT lost
    created_at          INTEGER NOT NULL,
    PRIMARY KEY (account_id, chat_id)
);
```

`server_last_read_id` is why marking a chat unread does not destroy the
underlying server read state (brief §44).

### Folders, notification prefs, undo

```sql
CREATE TABLE chat_folder (
    id          TEXT PRIMARY KEY,
    account_id  TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    icon        TEXT,
    filter_json TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_collapsed INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE notification_preference (
    account_id    TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    chat_id       INTEGER NOT NULL,
    muted_until   INTEGER,
    sound         TEXT,
    show_preview  INTEGER NOT NULL DEFAULT 1,
    focus_mode    TEXT,
    PRIMARY KEY (account_id, chat_id)
);

-- Reversible local transactions (brief §14)
CREATE TABLE undo_entry (
    id          TEXT PRIMARY KEY,
    account_id  TEXT    NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    operation   TEXT    NOT NULL,   -- delete_draft|delete_bookmark|delete_note|...
    payload_json TEXT   NOT NULL,   -- enough to reconstruct the row
    created_at  INTEGER NOT NULL,
    expires_at  INTEGER NOT NULL
);
```

Undo is a persisted record, not in-memory state, so "Undo" still works if the
window closes within the window.

---

## 3. Full-text search (FTS5)

GRDB enables FTS5 by default (`ARCHITECTURE.md` §1.4). Indexes **local-only**
content; remote message search is delegated to TDLib.

```sql
CREATE VIRTUAL TABLE local_search USING fts5(
    body,
    kind     UNINDEXED,   -- draft|draft_revision|note|archive|bookmark
    row_id   UNINDEXED,
    account_id UNINDEXED,
    chat_id  UNINDEXED,
    message_id UNINDEXED,
    tokenize = 'unicode61 remove_diacritics 2'
);
```

`remove_diacritics 2` matters for the launch languages: it lets Uzbek Latin
(`oʻ`, `gʻ`) and Russian queries match reliably regardless of input form.

Indexing runs **after** the write transaction commits, off the UI thread, driven
by the sync pipeline (brief §51).

---

## 4. Migrations

```swift
migrator.registerMigration("v1_foundation")   { /* account, draft, revisions */ }
migrator.registerMigration("v2_read_state")   { /* read state, viewers */ }
migrator.registerMigration("v3_archive")      { /* deletion events, archive */ }
migrator.registerMigration("v4_organization") { /* bookmarks, tags, notes */ }
migrator.registerMigration("v5_search")       { /* FTS5 + triggers */ }
```

Rules (brief §48):

1. Append-only. A shipped migration is never edited.
2. Additive. No destructive column/table drops on user data.
3. Every migration has a test asserting data survives it.
4. Failure leaves the database at the prior version and surfaces a recovery
   path — never a silent wipe (brief §78: "database migration fails").
5. A pre-migration backup is taken for any migration touching archive or drafts.

---

*Companion documents: `ARCHITECTURE.md`, `SECURITY_MODEL.md`, `PRODUCT_SPEC.md`.*
