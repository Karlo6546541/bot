-- Replace a chapter's page list in one transaction (reorder / add / remove).
-- SECURITY INVOKER: RLS on chapter_pages still applies (owner only).
create or replace function public.replace_chapter_pages(p_chapter uuid, p_pages jsonb)
returns int language plpgsql security invoker set search_path = '' as $$
declare v_series uuid; v_count int;
begin
  if not public.owns_chapter(p_chapter) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select series_id into v_series from public.chapters where id = p_chapter;

  if exists (
    select 1 from jsonb_array_elements(p_pages) e
    where not (e ->> 'storage_path' like v_series::text || '/' || p_chapter::text || '/%')
  ) then
    raise exception 'invalid storage path' using errcode = '22023';
  end if;

  delete from public.chapter_pages where chapter_id = p_chapter;
  insert into public.chapter_pages (chapter_id, position, storage_path, width, height)
  select p_chapter, (ord - 1)::int, e ->> 'storage_path', (e ->> 'width')::int, (e ->> 'height')::int
    from jsonb_array_elements(p_pages) with ordinality as t(e, ord);
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke execute on function public.replace_chapter_pages(uuid, jsonb) from public, anon;
grant execute on function public.replace_chapter_pages(uuid, jsonb) to authenticated;
