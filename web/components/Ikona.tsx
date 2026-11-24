/** Ikona iz Material Icons fonta (isti font kao u Flutter aplikaciji). */
export function Ikona({ k, velicina, boja }: { k: number; velicina?: number; boja?: string }) {
  return (
    <span className="mi" aria-hidden="true" style={velicina || boja ? { fontSize: velicina, color: boja } : undefined}>
      {String.fromCodePoint(k)}
    </span>
  );
}
