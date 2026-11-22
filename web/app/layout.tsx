import type { ReactNode } from 'react';

// Pravi layout (html, jezik, navigacija) je u app/[lang]/layout.tsx; ovaj samo prosljeđuje.
export default function Korijen({ children }: { children: ReactNode }) {
  return children;
}
