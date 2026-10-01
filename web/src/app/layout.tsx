import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Nodogram',
  description:
    'A fast, private, keyboard-first Telegram client that runs entirely in your browser.',
  applicationName: 'Nodogram',
  // No server holds user data, so there is nothing for a crawler to index and
  // no reason for this to appear in search results.
  robots: { index: false, follow: false },
  icons: {
    icon: [
      { url: '/icon.svg', type: 'image/svg+xml' },
      { url: '/favicon.svg', type: 'image/svg+xml', sizes: 'any' },
    ],
    apple: [{ url: '/icon.svg' }],
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  // The composer must not zoom the layout on mobile when focused.
  maximumScale: 1,
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#fbfbfe' },
    { media: '(prefers-color-scheme: dark)', color: '#1b1b23' },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
