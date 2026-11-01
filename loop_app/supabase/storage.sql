-- LOOP: spremište fotografija (Supabase Storage). Isti dio je i na kraju
-- supabase/schema.sql — dovoljno je pokrenuti schema.sql.
-- Javni bucket "loop-images": čitati smiju svi, dodavati i brisati samo
-- prijavljeni korisnici. Smije se pokrenuti više puta.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'loop-images', 'loop-images', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "loop_images_test_read" on storage.objects;
create policy "loop_images_test_read" on storage.objects
  for select to anon, authenticated using (bucket_id = 'loop-images');

drop policy if exists "loop_images_test_insert" on storage.objects;
create policy "loop_images_test_insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'loop-images');

drop policy if exists "loop_images_test_delete" on storage.objects;
create policy "loop_images_test_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'loop-images');
