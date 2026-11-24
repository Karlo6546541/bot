import { notFound } from 'next/navigation';

// Sve nepoznate adrese idu na stranicu "nije pronađeno" u izgledu stranice (s navigacijom).
export default function Nepostojeca() {
  notFound();
}
