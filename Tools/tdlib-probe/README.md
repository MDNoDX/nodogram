# tdlib-probe

Smoke test that the pinned TDLib actually loads and reports itself.

```bash
swift run --package-path Tools/tdlib-probe tdlib-probe
```

Expected:

```
TDLib probe OK
  version : 1.8.67
  commit  : 42e6a5259551178d1dab54a22ad96d14bd906e20
```

Exits `0` on success, `1` with a reason on failure. Run it after every
dependency bump and compare against `Documentation/UPSTREAM.md` §1.

It is also a deliberate miniature of the real Telegram gateway: it demonstrates
why the non-`Sendable` `TDLibClient` must be confined inside a single
`Sendable`-by-contract type. See `Documentation/ARCHITECTURE.md` §1.3.

> The first run downloads a ~300 MB TDLib xcframework.
