import { prevedi, type Jezik } from '@/lib/i18n';
import { jeIstekao } from '@/lib/pretraga';
import type { Oglas } from '@/lib/types';

export function StatusOznaka({ oglas, jezik = 'hr' }: { oglas: Pick<Oglas, 'status' | 'istjece'>; jezik?: Jezik }) {
  const t = (s: string) => prevedi(jezik, s);
  if (oglas.status === 'prodano') return <span className="oznaka">{t('Prodano')}</span>;
  if (oglas.status === 'uklonjen') return <span className="oznaka crvena">{t('Uklonjen')}</span>;
  if (oglas.status === 'obrisan') return <span className="oznaka siva">{t('Obrisan')}</span>;
  if (jeIstekao(oglas as Oglas)) return <span className="oznaka siva">{t('Istekao')}</span>;
  return <span className="oznaka">{t('Aktivan')}</span>;
}
