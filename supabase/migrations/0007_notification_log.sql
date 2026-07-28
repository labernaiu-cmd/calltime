-- Call Time — dedupe log for scheduled notifications (api/cron/tick.js).
-- The after_absence/before_event notification_rules triggers run on a
-- timer rather than a single user action, so without this they'd re-fire
-- on every cron tick after the condition first becomes true.
create table notification_log (
  id uuid primary key default gen_random_uuid(),
  ensemble_id uuid references ensembles(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  rule_id uuid references notification_rules(id) on delete cascade,
  event_id uuid references events(id) on delete cascade,
  sent_at timestamptz default now()
);

-- before_event: at most one send per (rule, event, student).
create unique index notification_log_event_key
  on notification_log (rule_id, user_id, event_id)
  where event_id is not null;

-- after_absence: at most one send per (rule, student) — it's about
-- crossing an absence-count threshold, not tied to a single event.
create unique index notification_log_no_event_key
  on notification_log (rule_id, user_id)
  where event_id is null;

-- Only the cron job's service-role key touches this table (see
-- api/cron/tick.js) — no policies, so RLS denies the anon/authenticated
-- roles entirely by default, rather than exposing "who got warned about
-- absences" over the public API.
alter table notification_log enable row level security;
