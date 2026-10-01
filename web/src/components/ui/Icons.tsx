/**
 * Inline SVG icons.
 *
 * Inline rather than an icon package: it keeps the bundle small, and every icon
 * inherits `currentColor` so theming needs no per-icon work.
 */

type IconProps = { className?: string; size?: number };

function Svg({
  children,
  className,
  size = 16,
}: IconProps & { children: React.ReactNode }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

export const Icon = {
  Chats: (p: IconProps) => (
    <Svg {...p}>
      <path d="M8 10h8M8 14h5" />
      <path d="M21 12a8 8 0 0 1-8 8H5l-2 2V12a8 8 0 0 1 8-8h2a8 8 0 0 1 8 8Z" />
    </Svg>
  ),
  Unread: (p: IconProps) => (
    <Svg {...p}>
      <circle cx="12" cy="12" r="5" fill="currentColor" stroke="none" />
    </Svg>
  ),
  Person: (p: IconProps) => (
    <Svg {...p}>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21a8 8 0 0 1 16 0" />
    </Svg>
  ),
  Group: (p: IconProps) => (
    <Svg {...p}>
      <circle cx="9" cy="8" r="3.5" />
      <path d="M2 20a7 7 0 0 1 14 0" />
      <path d="M17 11a3 3 0 1 0-2-5.2M18 20a6.5 6.5 0 0 0-2-4.7" />
    </Svg>
  ),
  Channel: (p: IconProps) => (
    <Svg {...p}>
      <path d="M4 10v4a1 1 0 0 0 1 1h3l5 4V5L8 9H5a1 1 0 0 0-1 1Z" />
      <path d="M17 9a4 4 0 0 1 0 6" />
    </Svg>
  ),
  Bookmark: (p: IconProps) => (
    <Svg {...p}>
      <path d="M6 4h12v17l-6-4-6 4V4Z" />
    </Svg>
  ),
  Archive: (p: IconProps) => (
    <Svg {...p}>
      <rect x="3" y="4" width="18" height="4" rx="1" />
      <path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8M10 12h4" />
    </Svg>
  ),
  Draft: (p: IconProps) => (
    <Svg {...p}>
      <path d="M12 20h8" />
      <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4Z" />
    </Svg>
  ),
  Star: (p: IconProps) => (
    <Svg {...p}>
      <path d="m12 3 2.7 5.5 6.1.9-4.4 4.3 1 6.1-5.4-2.9-5.4 2.9 1-6.1L3.2 9.4l6.1-.9Z" />
    </Svg>
  ),
  History: (p: IconProps) => (
    <Svg {...p}>
      <path d="M3 12a9 9 0 1 0 3-6.7L3 8" />
      <path d="M3 3v5h5M12 7v5l3 2" />
    </Svg>
  ),
  Settings: (p: IconProps) => (
    <Svg {...p}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1A1.6 1.6 0 0 0 9 19.4a1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1A1.6 1.6 0 0 0 4.6 9a1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1Z" />
    </Svg>
  ),
  Search: (p: IconProps) => (
    <Svg {...p}>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" />
    </Svg>
  ),
  Send: (p: IconProps) => (
    <Svg {...p}>
      <path d="M5 12h14M13 6l6 6-6 6" />
    </Svg>
  ),
  Check: (p: IconProps) => (
    <Svg {...p}>
      <path d="m4 12 5 5L20 6" />
    </Svg>
  ),
  DoubleCheck: (p: IconProps) => (
    <Svg {...p}>
      <path d="m2 12 4.5 4.5L15 8" />
      <path d="m10 16 1.5 1.5L22 7" />
    </Svg>
  ),
  Clock: (p: IconProps) => (
    <Svg {...p}>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5l3 2" />
    </Svg>
  ),
  Warning: (p: IconProps) => (
    <Svg {...p}>
      <path d="M12 9v4M12 17h.01" />
      <path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z" />
    </Svg>
  ),
  Offline: (p: IconProps) => (
    <Svg {...p}>
      <path d="M2 2l20 20M8.5 16.5a5 5 0 0 1 7 0M5 13a10 10 0 0 1 3-2M19 13a10 10 0 0 0-7-2.9M2 8.8A15 15 0 0 1 6 6.3M22 8.8a15 15 0 0 0-8.6-2.7" />
      <path d="M12 20h.01" />
    </Svg>
  ),
  Paperclip: (p: IconProps) => (
    <Svg {...p}>
      <path d="M21 11.5 12.5 20a5.5 5.5 0 0 1-7.8-7.8l8.5-8.5a3.5 3.5 0 1 1 5 5L9.6 17.3a1.5 1.5 0 0 1-2.2-2.2l7.9-7.9" />
    </Svg>
  ),
  Pin: (p: IconProps) => (
    <Svg {...p}>
      <path d="M12 17v5M9 3h6l-1 6 3 3H7l3-3-1-6Z" />
    </Svg>
  ),
  Mute: (p: IconProps) => (
    <Svg {...p}>
      <path d="M2 2l20 20" />
      <path d="M18 8a6 6 0 0 0-9.3-5M6 9v5l-2 3h12M9 21a3 3 0 0 0 5 0" />
    </Svg>
  ),
  Verified: (p: IconProps) => (
    <Svg {...p}>
      <path d="m12 2 2.4 2.1 3.2-.3.9 3.1 2.8 1.6-1.3 2.9 1.3 2.9-2.8 1.6-.9 3.1-3.2-.3L12 22l-2.4-2.1-3.2.3-.9-3.1L2.7 15.5 4 12.6 2.7 9.7l2.8-1.6.9-3.1 3.2.3Z" />
      <path d="m9 12 2 2 4-4" />
    </Svg>
  ),
  Key: (p: IconProps) => (
    <Svg {...p}>
      <circle cx="7.5" cy="15.5" r="4.5" />
      <path d="m10.5 12.5 9-9M17 6l2.5 2.5M14.5 8.5 17 11" />
    </Svg>
  ),
  Logo: (p: IconProps) => (
    <Svg {...p}>
      <rect x="3" y="4" width="13" height="8" rx="2.5" opacity="0.35" />
      <rect x="5.5" y="8" width="13" height="8" rx="2.5" opacity="0.6" />
      <path d="M8 12h13a2.5 2.5 0 0 1 2.5 2.5v3A2.5 2.5 0 0 1 21 20H11l-3 2.5V20a2.5 2.5 0 0 1-2.5-2.5v-3A2.5 2.5 0 0 1 8 12Z" />
    </Svg>
  ),
};
