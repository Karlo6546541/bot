import type { Metadata } from 'next';
import { ObjaviForma } from '@/components/ObjaviForma';

import { jezik, prevedi } from '@/lib/i18n';

export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }): Promise<Metadata> {
  return { title: prevedi(jezik((await params).lang), 'Objavi oglas'), robots: { index: false } };
}

export default function Objavi() {
  return <ObjaviForma />;
}
