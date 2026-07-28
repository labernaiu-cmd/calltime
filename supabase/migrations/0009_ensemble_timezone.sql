-- Call Time — events/attendance have no timezone column, so
-- api/cron/tick.js (running on Vercel's UTC clock) was doing all of its
-- "has this event ended yet" / "is it time for this reminder" math as if
-- event_date/start_time/end_time were UTC wall-clock times. That's wrong
-- for every ensemble not physically in UTC — auto-checkout and
-- before_event/after_absence-adjacent timing could fire hours off from
-- the real rehearsal. events.event_date/start_time/end_time stay
-- unqualified (a rehearsal's clock time doesn't change), but the
-- ensemble itself now carries the IANA timezone that clock time is in.
alter table ensembles
  add column tz text not null default 'America/Chicago';
