# Upstream Tracking

Keeps future upstream synchronization manageable (brief §84). Update this file
in the **same commit** as any dependency bump.

---

## 1. Current pins

Verified 2026-10-01 by inspecting upstream sources and building on the target machine.

| Component | Repository | Pinned version | Resolved revision | License |
|---|---|---|---|---|
| TDLib | `github.com/tdlib/td` | `1.8.67` | commit `42e6a5259551178d1dab54a22ad96d14bd906e20` | BSL-1.0 |
| TDLibFramework | `github.com/Swiftgram/TDLibFramework` | `1.8.67-0efabf93` | `9ebb0e55a3607f10f24b3fc3e663bd38e7743ad2` | MIT |
| TDLibKit | `github.com/Swiftgram/TDLibKit` | `1.5.2-tdlib-1.8.67-0efabf93` | `b03132690b427a0bc54fd15307cdd22c7e4b4445` | MIT |
| GRDB.swift | `github.com/groue/GRDB.swift` | `7.11.0` | (added in Phase 2) | MIT |

Revisions above are copied from `Tools/tdlib-probe/Package.resolved`, which is
committed so resolution is reproducible.

### Version suffixes are a trap

`TDLibFramework 1.8.67-0efabf93` does **not** package TDLib commit `0efabf93`.
That suffix is TDLibFramework's own build identifier; the TDLib commit inside is
`42e6a525…`, which only the running binary reports. Never infer the TDLib commit
from a package version — run the probe (§5).

**Runtime-verified:** TDLib reports `version = 1.8.67`,
`commit_hash = 42e6a5259551178d1dab54a22ad96d14bd906e20`, **MTProto layer 229**,
database version 14 — observed by running `Tools/tdlib-probe` on macOS 26.5 /
Xcode 26.6 / Swift 6.3.3 / Apple M1 Pro.

**Local modifications: none.** All three TDLib-related components are consumed
unmodified, as binary/source packages. We have vendored no upstream code.

---

## 2. Trap: TDLibKit version ranges do not work

TDLibKit tags are SemVer **prereleases** (`1.5.2-tdlib-1.8.67-0efabf93`).
SPM will not match them with a range. This fails:

```swift
.package(url: "…/TDLibKit", from: "1.8.67")
// error: Dependencies could not be resolved because no versions of
// 'tdlibkit' match the requirement 1.8.67..<2.0.0
```

Always pin exactly:

```swift
.package(url: "https://github.com/Swiftgram/TDLibKit",
         exact: "1.5.2-tdlib-1.8.67-0efabf93")
```

Note the leading `1.5.2` is **TDLibKit's own** version; the embedded
`tdlib-1.8.67` names the wrapped TDLib. They advance independently.

---

## 3. Upgrade procedure

1. Read TDLib's `CHANGELOG.md` between the pinned and target versions. Watch for
   **MTProto layer** changes and removed/renamed `td_api` entries.
2. Find the matching `TDLibKit` tag (its suffix names TDLibFramework's build, which is NOT the TDLib commit — confirm the TDLib commit by running the probe).
3. Bump `exact:` in `Package.swift`; update §1 above.
4. Build. Generated-API breakage appears as compile errors in
   `Nodogram/Telegram/Mapping` **only** — if an error appears above that layer,
   the layering rule has been violated and that is the bug to fix first
   (`ARCHITECTURE.md` §2).
5. Run the full test suite, especially sync ordering, duplicates, and migrations.
6. Re-run the probe in §5 and confirm the reported version/commit/layer.
7. Record the result in §4.

### Why breakage is contained

TDLib's `td_api.tl` is ~16,300 lines and TDLibKit regenerates Swift types from
it, so an upgrade can rename or remove many types at once. The mapping layer
exists precisely to absorb that: domain types are ours and do not move.

---

## 4. Upgrade log

| Date | From | To | Notes |
|---|---|---|---|
| 2026-10-01 | — | TDLib 1.8.67 / TDLibKit `1.5.2-tdlib-1.8.67-0efabf93` | Initial pin. Verified by running probe (§5). |

---

## 5. Verification probe

Minimal check that a pinned TDLib actually loads and reports itself. Keep it
working; it is the cheapest possible upgrade smoke test.

```swift
// TDLib answers nothing until setTdlibParameters, but version/commit_hash
// arrive unsolicited as updateOption pushes — so observe UPDATES, do not
// await a getOption response (it will hang). See ARCHITECTURE.md §1.2.
let manager = TDLibClientManager()
let client = manager.createClient { data, _ in
    if let s = String(data: data, encoding: .utf8), s.contains("updateOption") {
        print(s)   // look for version, commit_hash
    }
}
```

Expected, on a correct pin:

```
Create Td with layer 229, database version 14 and version 61 on 4 threads
updateOption { name = "version"     value = "1.8.67" }
updateOption { name = "commit_hash" value = "42e6a525…" }
updateAuthorizationState { authorizationStateWaitTdlibParameters {} }
```

---

## 6. Reference-only upstreams — never merged

Studied for protocol and interaction understanding. **No code is taken.** They
are listed so the boundary stays visible and auditable.

| Repository | License | Status |
|---|---|---|
| `overtake/TelegramSwift` | GPL-2.0-or-later | Reference only — copyleft (`LEGAL_AND_LICENSES.md` §1) |
| `telegramdesktop/tdesktop` | GPL-3.0 + OpenSSL exception | Reference only |
| `desktop-app/tg_owt`, `tgcalls` | BSD/Apache/MIT mix | Not used; would be needed for call media (`ARCHITECTURE.md` §10.1) |

There is **no merge strategy** for these, by design. Adopting any of their code
would change Nodogram's license and forfeit App Store distribution.
