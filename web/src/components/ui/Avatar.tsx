/**
 * Initial-based avatar.
 *
 * The colour is derived from the chat id, so the same chat keeps the same
 * colour across reloads without storing anything.
 */

const PALETTE = [
  'oklch(0.55 0.15 275)',
  'oklch(0.55 0.13 190)',
  'oklch(0.58 0.14 330)',
  'oklch(0.62 0.14 60)',
  'oklch(0.55 0.13 240)',
  'oklch(0.57 0.13 300)',
];

function hash(value: string): number {
  let h = 0;
  for (let i = 0; i < value.length; i += 1) {
    h = (h << 5) - h + value.charCodeAt(i);
    h |= 0;
  }
  return Math.abs(h);
}

function initials(title: string): string {
  const words = title.trim().split(/\s+/).slice(0, 2);
  const letters = words.map((w) => [...w][0]).filter(Boolean);
  return letters.length > 0 ? letters.join('').toUpperCase() : '?';
}

export function Avatar({
  title,
  id,
  size = 40,
}: {
  title: string;
  id: string;
  size?: number;
}) {
  const color = PALETTE[hash(id) % PALETTE.length];
  return (
    <div
      className="flex shrink-0 items-center justify-center rounded-full font-medium text-white select-none"
      style={{
        width: size,
        height: size,
        background: color,
        fontSize: size * 0.38,
      }}
      /* The chat name is already announced by the row label; repeating the
         initials would just be noise for screen-reader users. */
      aria-hidden="true"
    >
      {initials(title)}
    </div>
  );
}
