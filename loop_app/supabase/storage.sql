-- LOOP: spremište fotografija predmeta (Supabase Storage) — SAMO ZA TEST.
-- Javni bucket "loop-images": svatko s javnim ključem smije čitati,
-- dodavati i brisati slike u njemu. Smije se pokrenuti više puta.
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
  for insert to anon, authenticated with check (bucket_id = 'loop-images');

drop policy if exists "loop_images_test_delete" on storage.objects;
create policy "loop_images_test_delete" on storage.objects
  for delete to anon, authenticated using (bucket_id = 'loop-images');
