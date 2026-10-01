import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Nodogram Web runs entirely in the browser: GramJS speaks MTProto directly
  // from the client, and all data lives in IndexedDB. No server component ever
  // holds user data, which is what keeps the privacy model intact.
  turbopack: {
    resolveAlias: {
      // GramJS reaches Node built-ins through its optional SOCKS-proxy support,
      // which the browser never uses (it connects over WebSocket). The bundler
      // still has to resolve the imports, so they are stubbed.
      // See src/lib/node-stub.ts.
      fs: './src/lib/node-stub.ts',
      net: './src/lib/node-stub.ts',
      tls: './src/lib/node-stub.ts',
      dns: './src/lib/node-stub.ts',
    },
  },
};

export default nextConfig;
