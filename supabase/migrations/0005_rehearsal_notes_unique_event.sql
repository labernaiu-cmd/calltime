-- Call Time — rehearsal notes are one row per event (pre/post notes for
-- that rehearsal), but the original schema had no unique constraint to
-- upsert against. savePreNotes()/savePostNotes() need `.upsert(...,
-- {onConflict: 'event_id'})` to work.
create unique index rehearsal_notes_event_id_key on rehearsal_notes (event_id);
