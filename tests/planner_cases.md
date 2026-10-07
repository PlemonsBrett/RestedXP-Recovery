# Planner acceptance cases

These cases define expected behavior for the pure `Planner.Resolve` module.

## Linear chain

If quest 300 requires 200 and quest 200 requires 100, and none are complete:

- target: 300, carryover
- expected plan: 100 -> 200 -> 300

## Completed prerequisite

If quest 300 requires 200, but 200 is already turned in:

- target: 300, carryover
- expected plan: 300

## Upcoming accept

If the current guide itself contains the accept for quest 300, and 300 requires 200:

- target: 300, accept
- expected plan: 200
- quest 300 must not be duplicated in the recovery plan

## OR prerequisites

If quest 300 can be unlocked by either 200 or 250:

- if either is already turned in, no prerequisite recovery is needed;
- if 250 is currently in the quest log, prefer 250;
- otherwise select the branch with fewer recursively outstanding quests.

## AND prerequisites

If quest 300 requires both 200 and 250:

- resolve both branches before 300.

## Cycle protection

Malformed dependency data must produce a warning rather than recurse forever.

## Route extraction

- a prerequisite quest includes its accept, objective, and turn-in steps;
- a carry-over target stops after its accept step so the original guide can handle it;
- unrelated quest actions sharing a source step are removed;
- source guide tables are not mutated;
- guide-control and XP directives are not copied into temporary routes.

## XP recovery

- the first unmet explicit XP step is the primary deficit signal;
- a guide's ending level is used only in the final 15% of the guide;
- completed, active, unavailable, trivial, and excessively high-level quests are excluded;
- candidates with known XP rewards sort ahead of lower-value candidates.
