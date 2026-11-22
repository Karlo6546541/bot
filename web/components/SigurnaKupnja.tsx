'use client';
import { useJezik } from './Jezik';

export function SigurnaKupnja() {
  const { t } = useJezik();
  return (
    <aside className="upozorenje" aria-label={t('Savjeti za sigurnu kupnju')}>
      <strong>{t('Sigurna kupnja')}</strong>
      <ul>
        <li>{t('Najsigurnije je osobno preuzimanje: pregledaj predmet prije plaćanja.')}</li>
        <li>{t('Budi oprezan kod plaćanja unaprijed i nikad ne šalji podatke kartice ni kodove.')}</li>
        <li>{t('Kod skupljih predmeta traži dodatne fotografije, certifikat ili dokaz porijekla.')}</li>
        <li>{t('Sumnjiv oglas prijavi gumbom "Prijavi oglas".')}</li>
      </ul>
    </aside>
  );
}
