-- Call Time — lets a teacher decide (in the setup wizard, or later in
-- Settings > Grading) whether an approved excuse removes that absence
-- from the free-absence/failing-threshold and grade-deduction math, or
-- whether it still counts the same as an unexcused one. Defaults to
-- excluding it (true), matching typical academic policy.
alter table grading_policies
  add column exclude_excused_absences boolean default true;
