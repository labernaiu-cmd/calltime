-- Call Time — a third grading model alongside pct/letter: a points pool a
-- student either earns toward or has deducted from, e.g. "1000 points
-- total, 5 points per rehearsal." Selected in Settings > Grading
-- (gm-points), same place the pct/letter choice already lives.
alter table grading_policies
  add column points_total integer default 1000,
  add column points_per_event integer default 5,
  add column points_mode text default 'deduct'; -- 'deduct' | 'earn'
