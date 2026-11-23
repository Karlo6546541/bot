/** Javi poslužitelju da osvježi keširane stranice (početna, kategorije, oglas). Greška se ignorira. */
export function osvjeziStranice(oglasId?: string) {
  return fetch('/api/osvjezi', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ oglasId }), keepalive: true }).catch(() => undefined);
}
