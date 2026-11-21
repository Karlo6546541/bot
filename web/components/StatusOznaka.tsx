import { jeIstekao } from '@/lib/pretraga';
import type { Oglas } from '@/lib/types';

export function StatusOznaka({ oglas }: { oglas: Pick<Oglas, 'status' | 'istjece'> }) {
  if (oglas.status === 'prodano') return <span className="oznaka">Prodano</span>;
  if (oglas.status === 'uklonjen') return <span className="oznaka crvena">Uklonjen</span>;
  if (oglas.status === 'obrisan') return <span className="oznaka siva">Obrisan</span>;
  if (jeIstekao(oglas as Oglas)) return <span className="oznaka siva">Istekao</span>;
  return <span className="oznaka">Aktivan</span>;
}
