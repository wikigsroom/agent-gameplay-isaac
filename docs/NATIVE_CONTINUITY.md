# Native bridge continuity

The bridge retains its original read-only Lua/render execution boundaries while
keeping hot Lua callbacks inside a native CModule when no trusted host request is
queued. Render timing and pending work counters are observations, not gameplay
values. Duplicate swap exports do not attach duplicate handlers.

Ordinary menu keys now include Space, with the same process/window identity check
and 140 ms lease as other allowed menu keys. Keyboard hooks are removed after the
last lease expires; an old release timer cannot clear a newer press of that key.
No arbitrary key, console restart, save or gameplay write is introduced.

The native controller retains the actual MC_POST_GAME_END receipt and emits its
real state during a frozen terminal screen. A real new-run callback clears that
receipt. It does not fabricate a victory or automatically enable gameplay. A
host may use its separately authorized live lifecycle to perform ordinary retry
input and rebind the next observed writable slot 3. A service restart alone does
not authorize this. Other hosts retain their observation-only startup behavior.

The livestream application owns its independent supervisor and visual title/file
selection guard; those application-specific modules are not part of this game
controller repository. Unknown menu images authorize no gameplay.

Regression coverage exercises native boundaries, stack restoration, render hook
aliases, input expiry and generated Lua 5.3 compilation. Real deployment and
public-live results are recorded separately in the livestream repository.
