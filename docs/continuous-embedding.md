# Continuous broadcast embedding

An embedding application that must keep its running game alive can explicitly set
`_G.ISAAC_ALLOW_AUTOMATIC_GAME_PAUSE=false` before installing the native controller.
Automatic lease-expiry pause requests then return `automatic_pause_forbidden` and
never press Escape or latch a pause. Expired utility-item authorizations still
expire normally; this option does not grant strategic decisions to local rules.

An explicit human pause can call `requestPause(id,true)` and retains the ordinary
observed-pause acknowledgement. Manual takeover remains available. The embedding
application must replace failed components independently and preserve a living
game. An actually exited game may be launched again through the normal menu.

With the flag absent or true, the existing standalone safe-pause behavior is
unchanged. This is an opt-in integration policy, not a change to standalone
startup or save protection. No credentials, model service, game values or saves
are included or altered.

## Input admission and observation

An embedding that waits for its DSH host or other startup checks should create
`Controller(require_enabled_action_feedback=True)`. Observation still updates
the room and candidates, while disabled inputs do not count as failed movement,
pickup, hazard or door attempts. Changing input authority resets only ongoing
feedback timers; real prior unreachable targets remain recorded. Enabled
attempts still use the ordinary no-progress limits. The standalone default
remains compatible with existing diagnostic replays.

For slower strategic hosts, an embedding may explicitly construct
`StrategyService(decision_seconds=120,max_decision_seconds=120,renew_expired_decisions=True)`.
The window remains bounded at 120 seconds. An unsubmitted expired choice gets
a new decision identity and freshly validated offers; old plans remain invalid.
An issued command is never retried by this option. Defaults remain a 60-second
maximum and the existing expiration policy.

## Real endings and human ownership

`MC_POST_GAME_END` now reports the actual `manual_override` flag. A successful
ending disables automatic/controller input without changing that flag; only
the real F8 handler changes human takeover. A prior explicit human takeover
survives both the terminal callback and the existing new-run reset. Death
callback defaults are unchanged. An embedding may read the trusted current
Lua flag during menus, where ordinary game-state packets no longer arrive.

An embedding that continues a victory must navigate the real title and file
selection with ordinary input, confirm FILE 3 visually and the writable slot
natively, then verify a genuinely new living run before rearming. These
observations do not authorize changing saves or restarting a living process.
