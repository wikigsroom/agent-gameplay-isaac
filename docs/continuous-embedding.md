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
