/** Small inline SVG icon set (stroke = currentColor). Decorative: aria-hidden. */
type P = { className?: string };
const base = {
  width: 22,
  height: 22,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2.2,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

export const HomeIcon = ({ className }: P) => (
  <svg {...base} className={className}><path d="M3 11.5 12 4l9 7.5" /><path d="M5.5 10.5V20h13v-9.5" /></svg>
);
export const SearchIcon = ({ className }: P) => (
  <svg {...base} className={className}><circle cx="11" cy="11" r="6.5" /><path d="m20 20-4.2-4.2" /></svg>
);
export const LibraryIcon = ({ className }: P) => (
  <svg {...base} className={className}><rect x="4" y="4" width="6" height="16" rx="1" /><rect x="13" y="4" width="7" height="16" rx="1" /></svg>
);
export const StarIcon = ({ className }: P) => (
  <svg {...base} className={className}><path d="m12 3.5 2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.9 6.8 19.7l1-5.9-4.3-4.1 5.9-.8z" /></svg>
);
export const UserIcon = ({ className }: P) => (
  <svg {...base} className={className}><circle cx="12" cy="8" r="4" /><path d="M4.5 20c1-4 4-5.5 7.5-5.5s6.5 1.5 7.5 5.5" /></svg>
);
export const PenIcon = ({ className }: P) => (
  <svg {...base} className={className}><path d="M4 20l4-1 11-11-3-3L5 16z" /><path d="m14 7 3 3" /></svg>
);
export const LockIcon = ({ className }: P) => (
  <svg {...base} className={className}><rect x="5" y="10.5" width="14" height="9.5" rx="2" /><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" /></svg>
);
export const CoinIcon = ({ className }: P) => (
  <svg {...base} className={className} fill="currentColor" fillOpacity={0.18}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5v9M9.5 9.8c0-1 1-1.6 2.5-1.6s2.5.6 2.5 1.6-1 1.4-2.5 1.8-2.5.8-2.5 1.8 1 1.6 2.5 1.6 2.5-.6 2.5-1.6" strokeWidth={1.6} /></svg>
);
export const CheckIcon = ({ className }: P) => (
  <svg {...base} className={className}><path d="m5 12.5 4.5 4.5L19 7.5" /></svg>
);
export const ArrowLeftIcon = ({ className }: P) => (
  <svg {...base} className={className}><path d="M19 12H5M11 6l-6 6 6 6" /></svg>
);
export const ArrowRightIcon = ({ className }: P) => (
  <svg {...base} className={className}><path d="M5 12h14M13 6l6 6-6 6" /></svg>
);
export const PlayIcon = ({ className }: P) => (
  <svg {...base} className={className} fill="currentColor"><path d="M8 5.5v13l11-6.5z" /></svg>
);
export const PlusIcon = ({ className }: P) => (
  <svg {...base} className={className}><path d="M12 5v14M5 12h14" /></svg>
);
