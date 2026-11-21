import type { Metadata } from 'next';
import { ObjaviForma } from '@/components/ObjaviForma';

export const metadata: Metadata = { title: 'Objavi oglas', robots: { index: false } };

export default function Objavi() {
  return <ObjaviForma />;
}
