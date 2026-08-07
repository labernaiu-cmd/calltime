-- Call Time — real file storage for excuse attachments.
-- Previously the client embedded the file as a base64 data: URL directly
-- in excuses.attachment_url — works for a tiny photo, bloats the table for
-- anything bigger and was never a real upload. Files now go to a private
-- Storage bucket at <ensemble_id>/<user_id>/<timestamp>-<filename>, and
-- attachment_url stores that path (resolved to a signed URL client-side
-- when displaying it — see loadExcusesFromDB() / submitExc()).
insert into storage.buckets (id, name, public)
values ('excuse-attachments', 'excuse-attachments', false)
on conflict (id) do nothing;

create policy "Students can upload their own excuse attachments"
  on storage.objects for insert
  with check (
    bucket_id = 'excuse-attachments'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "Owners and their ensemble's teacher can view excuse attachments"
  on storage.objects for select
  using (
    bucket_id = 'excuse-attachments'
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or is_ensemble_teacher(((storage.foldername(name))[1])::uuid)
    )
  );

create policy "Students can delete their own excuse attachments"
  on storage.objects for delete
  using (
    bucket_id = 'excuse-attachments'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
