import unittest
from pathlib import Path


class LuaNavigationTests(unittest.TestCase):
    def test_moving_spike_blocks_are_avoided_but_never_targeted_as_enemies(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('EntityType.ENTITY_POKY or 44', source)
        self.assertIn('EntityType.ENTITY_WALL_HUGGER or 218', source)
        self.assertIn('if hazardKind(entity) or isMovingSpikeTrap(entity) or isStoneTrap(entity)', source)
        self.assertIn('kind = "moving_spike"', source)
        self.assertIn('return false, "moving_spike"', source)
        self.assertIn('if liveAim:Length() <= 0.5 then fireBlockReason = "no_combat_target" end', source)
        self.assertIn('fireBlockReason = "movement_only_action"', source)
        self.assertIn('and action.mode ~= "wait"', source)

    def test_stone_traps_and_extinguished_fire_are_not_targeted(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('EntityType.ENTITY_STONEHEAD or 42', source)
        self.assertIn('EntityType.ENTITY_STONE_EYE or 201', source)
        self.assertIn('EntityType.ENTITY_CONSTANT_STONE_SHOOTER or 202', source)
        self.assertIn('or isStoneTrap(entity)', source)

    def test_tracking_bomb_is_observed_and_evaded_without_interrupting_own_bomb_retreat(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('kind = "ghost_bomb"', source)
        self.assertIn('owner.Index == player.Index then return nil', source)
        self.assertIn('entity.Index == (bombEntity and bombEntity.Index or -1)', source)
        self.assertIn('local trackingBomb = nearestTrackingBomb(player)', source)
        self.assertIn('return false, "ghost_bomb"', source)
        self.assertIn('not trackingBombNearby and hasCombatEnemy()', source)
        self.assertIn('if not trackingBombNearby then tryDropBomb(player) end', source)
        self.assertIn('fireBlockReason = "ghost_bomb_retreat"', source)
        self.assertIn('and not bombRetreatActive and not ghostBombRetreatActive', source)
        self.assertIn('string.find(name, "dissapear", 1, true)', source)
        self.assertIn('"Dissapear3"', source)

    def test_blue_fire_is_bomb_only_and_collectible_pedestal_is_filtered(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('BLUE_FIRE_VARIANTS = { [2] = true, [12] = true }', source)
        self.assertIn('requires_bomb = bombOnlyFireKind(kind)', source)
        self.assertIn('player:GetNumBombs() <= 4', source)
        self.assertIn('if collectible and (tonumber(entity.SubType) or 0) <= 0 then return nil end', source)

    def test_purple_fire_is_bomb_only(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('PURPLE_FIRE_VARIANTS = { [3] = true, [13] = true }', source)
        self.assertIn('return kind == "blue_fire" or kind == "purple_fire"', source)
        self.assertIn('fireBlockReason = "special_fire_bomb_only"', source)

    def test_onoff_spikes_use_on_zero_state_and_collision_guard(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('SpikesOnOff enum is ON=0, OFF=1', source)
        self.assertIn('active = collidable and (state == nil or state == 0)', source)
        self.assertIn('local collidable = not collisionOk or tonumber(collision) ~= 0', source)

    def test_room_changes_use_native_door_input_only(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertNotIn("StartRoomTransition", source)
        self.assertNotIn("api_fallback", source)
        self.assertNotIn("door_fallback_frames", source)
        self.assertIn('transitionPhase = "native_door_only"', source)
        self.assertIn('transitionGate = "navigation_override"', source)
        self.assertIn('^open_chest_', source)
        self.assertIn('hidden_door_locked', source)
        self.assertIn('ignoredPickupIds = {}', source)
        self.assertIn('actionPickupStillPresent()', source)
        self.assertIn('native_input_blocked', source)
        self.assertIn('local leadFrames = math.min(12, math.max(1.5, distance / tearSpeed))', source)
        self.assertIn('tear_speed = player.ShotSpeed', source)
        self.assertIn("if action.move:Length() > 0.5 then", source)
        self.assertIn("Do not overwrite that first path step with", source)
        self.assertIn('GRID_ROCKT', source)
        self.assertIn('^bomb_hazard_', source)
        self.assertIn('player:FireBomb(player.Position, Vector(0, 0), player)', source)
        self.assertIn('player:AddBombs(-1)', source)
        self.assertNotIn('player:DropBomb(', source)
        self.assertIn('bombPlaced = true', source)
        self.assertIn('GRID_TRAPDOOR', source)
        self.assertIn('^enter_boss_exit_', source)
        self.assertIn('boss_exit_navigation', source)
        self.assertIn('if openOk and open == true then', source)
        self.assertIn('state.safe_move_directions = checks', source)
        self.assertIn('safeMoveCandidate(player, desired, false) and desired or Vector(0, 0)', source)
        self.assertIn('if action.mode == "recovery" and action.waypoint then', source)
        self.assertIn('lastMoveResolutionReason = "recovery_waypoint_reached"', source)
        self.assertIn('local canUnlock = lockOk and locked == true and keyDoor and player:GetNumKeys() > 0', source)
        self.assertIn('not open and not canUnlock', source)
        self.assertIn('math.abs(delta.Y) <= 42 and safeMoveCandidate(player, doorSide, false)', source)

    def test_experiment_observation_contract_is_wired(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn("seeds:GetStartSeed()", source)
        self.assertIn("room_visit_sequence = roomVisitSequence", source)
        self.assertIn("room_entered_frame = roomEnteredFrame", source)
        self.assertIn("room_cleared_frame = roomClearedFrame", source)
        self.assertIn("enemy_total_hp = enemyTotalHp", source)
        self.assertIn("enemy_kill_delta = enemyKillDelta", source)
        self.assertIn("damage_events = damageEvents", source)
        self.assertIn("damageEventLimit = 32", source)
        self.assertIn("entity.Index ~= player.Index", source)
        self.assertIn("ModCallbacks.MC_ENTITY_TAKE_DMG", source)

    def test_dynamic_grid_and_action_contract(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        for field in (
            "grid_events = gridEvents", "danger_grid_indices = dangerGridIndices",
            "door_open = open", "door_open_known = openKnown",
            "stage = level:GetStage()", "stage_type = level:GetStageType()",
            "dimension = currentDimension(level)", "weapon_type = currentWeapon",
            "bomb_placed = bombPlaced", "bomb_position = bombPosition",
        ):
            self.assertIn(field, source)
        self.assertIn('^press_button_', source)
        self.assertIn('^shoot_tnt_', source)
        self.assertIn('bombRoomKey == currentRoomKey()', source)
        self.assertIn('bombRetreatActive = bombNeedsRetreat and automatic', source)
        self.assertIn('and not bombRetreatActive and not ghostBombRetreatActive', source)
        self.assertNotIn('local nextBomb = action.mode == "bomb"', source)
        self.assertIn('safeMoveCandidate(player, candidate', source)
        self.assertIn('action.move:Length() > 0.5', source)
        self.assertIn('local needsTearFallback = currentWeapon == "tear"', source)

    def test_bomb_placement_requires_hit_range_and_a_stable_escape(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('if bombId and (distance < 24 or distance > 70) then return end', source)
        self.assertIn('if not escape then bombError = "no clear bomb escape corridor"; return end', source)
        self.assertIn('bombRetreatDirection = escape', source)
        self.assertIn('player.Velocity = Vector(0, 0)', source)
        self.assertIn('resolvedMove = escape', source)
        self.assertIn('if safeMoveCandidate(player, bombRetreatDirection, false, true) then', source)
        self.assertIn('bomb_active = bombStillLive()', source)
        self.assertIn('local surpriseEnemy = automatic and not bombNeedsRetreat and not trackingBombNearby and hasCombatEnemy()', source)
        self.assertIn('if surpriseEnemy then resolvedMove = Vector(0, 0) end', source)
        self.assertIn('if surpriseEnemy or action.mode == "combat" then', source)

    def test_boss_bomb_uses_live_target_and_escapes_away_from_enemies(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('is_boss = isBoss', source)
        self.assertIn('if bossId and (distance < 55 or distance > 110) then return end', source)
        self.assertIn('if action.sourceRoomIndex >= 0 and action.sourceRoomIndex ~= game:GetLevel():GetCurrentRoomIndex() then return end', source)
        self.assertIn('if not bossId and (not action.bombSite or player.Position:Distance(action.bombSite) > 14)', source)
        self.assertIn('local escape = bombEscapeDirection(player, preferred, bossId ~= nil)', source)
        self.assertIn('or dangerousCreep(entity) or liveHazardKind(entity) == "fire"', source)
        self.assertIn('and safeMoveCandidate(player, side, false, true) then return side end', source)

    def test_live_enemies_override_the_native_room_clear_flag(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('if #enemies > 0 then\n        roomClear = false', source)
        self.assertIn('if isCombatEnemy(entity) then\n            table.insert(enemies, entityTable(entity))', source)
        self.assertNotIn('if not roomClear and isCombatEnemy(entity)', source)
        self.assertNotIn('if game:GetRoom():IsClear() then return false end', source)
        self.assertNotIn('if not game:GetRoom():IsClear() then', source)
        self.assertIn('npc:IsActiveEnemy(false) or entity.Type == EntityType.ENTITY_SPIDER', source)

    def test_fire_approach_does_not_conflict_with_fire_lane(self):
        source = (Path(__file__).parents[1] / "mods" / "IsaacJev" / "main.lua").read_text(encoding="utf-8")
        self.assertIn('clearTearLane(player, target.Position, 65)', source)
        self.assertIn('math.max(36, (tonumber(player.Size) or 10) + (tonumber(entity.Size) or 15) + 8)', source)
        self.assertNotIn('hazardDelta:Length() < 90', source)
        self.assertIn('hazardLaneCorrection(player, hazardTarget, hazardId)', source)
        self.assertIn('fireDirection = target and clearTearLane(player, target.Position, 65)', source)
        self.assertIn('lastMoveResolutionReason = "hazard_lane_control"', source)
