-- Call Time — Phase 3: real-time attendance
-- Lets the teacher's Today view update live as students check in (spec §2.3)
-- without a page refresh, via supabase.channel(...).on('postgres_changes', ...).
-- Idempotent so re-running this migration (or applying it to a project where
-- the publication already includes the table) doesn't error.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'attendance'
  ) then
    alter publication supabase_realtime add table attendance;
  end if;
end $$;
