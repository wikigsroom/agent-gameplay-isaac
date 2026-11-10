# Large-room pit stalemate correction

The 2026-11-11 native gameplay observation stayed in stage 3, room 80, visit 42 with three stationary enemies at 20 HP each. Frames advanced and the weapon emitted shots, but the player remained about 282 units from the nearest enemy. There was no pending DSH choice.

The Python firing-lane planner admitted the current tile using nominal TearRange 360 minus 25 (335). The native movement planner capped engagement range at 235. Since tears cross pits but the player cannot, this disagreement prevented Python from supplying a route around the pits while the short native forecast could not make the detour on its own. The player also held Proptosis; nominal range alone is not evidence that a shot did useful damage.

`firing_position` now caps the lane range at the native planner's existing 235-unit ceiling. Shorter nominal ranges retain their lower bound. This creates a reachable cardinal waypoint around the pits, preserved by the ordinary movement-penalty path. No game statistics, saves, pickups or model ownership change.

The sanitized observed layout is `tests/fixtures/stage3-pit-range-stall.json`; the regression exercises real candidate generation and reachable waypoints. Offline replay and a live room clear must be reported separately. This patch does not prove coverage of every item combination or a complete run.

Independent repository validation note: the first synchronization candidate (40db83d) imported an integration-only observation cache and failed module loading. The corrected independent candidate applies the same range fix to its own navigation baseline, preserving its separate dependency surface. Re-run the entire independent Python and Node suites against the new committed candidate; the failed run remains historical evidence.

Validation assertion correction: a legitimate detour may return to the original horizontal row. The final replay checks a finite walking route longer than the direct distance, alongside its native-range waypoint and retained movement goal. The prior failed assertion is retained in historical logs; production navigation is unchanged for this re-test.

Live result: the integrated `issac` candidate `f059bf41c7febb480d7f09ea5bc8f7b4a237c0ab` cleared the observed three-enemy room at 05:05:41 Asia/Taipei, then entered room 79 at 05:06:24 on 2026-11-11. Subsequent observations covered rooms 67, 82 and boss room 78 with the same game process/seed and 8 half-hearts. The main frozen suites passed 1313 tests with 7 skips; this independent source commit `4475de6ca33537fa0e2a1855b8f3d5794ef7fe17` passed all 682 Python and four Node tests. See [sanitized live evidence](evidence/pit-stalemate-live-20261111.json). This is evidence for this repair and follow-on play, with long-term application acceptance still pending.


CYCLE42 follow-up: the same Proptosis run later stalled after killing Gurdy. Share the native weapon profile’s conservative engagement range with Python; see [the follow-up](PROPTOSIS_RANGE_STALEMATE.md). Test and live results remain pending until complete frozen validation.
