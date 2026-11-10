import { getI18n } from "@/lib/i18n/server";
import { createClient } from "@/lib/supabase/server";

export default async function Home() {
  const { t } = await getI18n();
  const supabase = await createClient();
  const { data } = await supabase.from("series").select("id, title").order("updated_at", { ascending: false });
  return (
    <section>
      <h1 className="h1">{t("home.heroTitle")}</h1>
      <ul className="mt-4 list-disc pl-6">{data?.map((s) => <li key={s.id}>{s.title}</li>)}</ul>
    </section>
  );
}
