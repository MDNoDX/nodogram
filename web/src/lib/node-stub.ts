// Empty stand-in for Node built-ins that GramJS imports but never uses in a
// browser.
//
// GramJS's dependency tree reaches `fs`, `net` and `tls` through its optional
// SOCKS-proxy support. In the browser it connects over WebSocket instead, so
// those code paths are never taken — but the bundler still has to resolve the
// imports. Aliasing them here keeps the bundle buildable without pulling in
// Node polyfills.
//
// This is safe only while we do not use a SOCKS proxy. If proxy support is
// ever added, it needs a browser-native implementation, not this stub.
const nodeStub = {};
export default nodeStub;
