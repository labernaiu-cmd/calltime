-- Lets a teacher archive an ensemble instead of only being able to delete
-- it outright. Archiving is just a hidden-from-the-default-list flag — it
-- doesn't touch RLS or block writes — so it's trivially reversible
-- (unarchive) unlike delete, which cascades through every table via the
-- ensemble_id foreign keys already declared `on delete cascade` in
-- 0001_init_schema.sql.
alter table ensembles add column archived_at timestamptz;
