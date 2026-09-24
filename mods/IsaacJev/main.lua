-- Isaac Jev: Repentance only. Requires Steam launch option --luadebug.
-- The high-frequency input callback only consumes cached local state; it never opens sockets.

local mod = RegisterMod("Isaac Jev", 1)
local game = Game()
local socketOk, socket = pcall(require, "socket")
local Json = _G.json
if not Json then
    local jsonOk, jsonModule = pcall(require, "json")
    if jsonOk then Json = jsonModule end
end

local HOST, PORT = "127.0.0.1", 9528
local client = nil
local pendingState = nil
local bridgeStatus = socketOk and (Json and "disconnected" or "json unavailable") or "socket unavailable"
local automatic = false
local manualOverride = false
local lastActionFrame = -10000
local action = { id = "", move = Vector(0, 0), shoot = Vector(0, 0), mode = "combat", target = "", reason = "", sourceRoomIndex = -1, targetRoomIndex = -1, ignoredHazardIds = {}, ignoredPickupIds = {} }
local bombTargetId = -1
local bombPlaced = false
local bombPlacedFrame = -1
local bombPosition = nil
local bombEntity = nil
local bombPlacementDistance = -1
local bombRetreatDirection = Vector(1, 0)
local bombRoomKey = ""
local bombRetreatActive = false
local ghostBombRetreatActive = false
local bombError = nil
local bombedWallKeys = {}
local lastLayoutRoom = -99999
local lastLayout = nil
local lastStateFrame = -99999
local sentStateCount = 0
local firedTearCount = 0
local fireError = nil
local fireBlockReason = "idle"
local MOD_VERSION = "2026-09-24-v18"
local fireDirection = Vector(0, 0)
local hazardLaneRoomKey = ""
local hazardLaneTargetId = -1
local hazardLaneAxis = ""
local nativeTearFrame = -10000
local nativeSeenTears = {}
local nativeFireStartFrame = -1
local resolvedMove = Vector(0, 0)
local lastRequestedMove = Vector(0, 0)
local lastResolvedMove = Vector(0, 0)
local lastMovementProgress = 0
local lastMovementBlocked = false
local lastMoveResolutionReason = "idle"
local lastPlayerPosition = nil
local transitionError = nil
local transitionGate = "idle"
local transitionDoorDistance = -1
local transitionPhase = "idle"
local transitionAttempt = 0
local doorAttemptRoomIndex = -1
local doorAttemptSlot = -1
local lastObservedRoomIndex = -99999
local lastTransitionSourceRoomIndex = -1
local lastTransitionTargetRoomIndex = -1
local roomEntryFrame = -10000
local backtrackGuardFrames = 180
local currentActionSequence = 0
local deathDetectedFrame = -1
local deathWaitTicks = 0
local restartAttempted = false
local restartCount = 0
local restartPhase = "alive"
local restartError = nil
local roomVisitSequence = 0
local roomEnteredFrame = -1
local roomClearedFrame = -1
local lastEnemyCount = 0
local damageEventSequence = 0
local damageEvents = {}
local damageEventLimit = 32
local lastUsedPill = {}
local pillUseResult = "idle"
local lastTrinketSwapTarget = -1
local trinketSwapResult = "idle"

local function startSeed()
    local ok, seeds = pcall(function() return game:GetSeeds() end)
    if not ok or not seeds then return 0 end
    local seedOk, seed = pcall(function() return seeds:GetStartSeed() end)
    if seedOk and seed then return tonumber(seed) or 0 end
    return 0
end

local function sourceMetadata(source)
    if not source then return -1, -1 end
    local typeOk, sourceType = pcall(function() return source.Type end)
    local variantOk, sourceVariant = pcall(function() return source.Variant end)
    if typeOk and sourceType ~= nil then
        return tonumber(sourceType) or -1, variantOk and (tonumber(sourceVariant) or -1) or -1
    end
    local entityOk, entity = pcall(function() return source.Entity end)
    if not entityOk or not entity then return -1, -1 end
    typeOk, sourceType = pcall(function() return entity.Type end)
    variantOk, sourceVariant = pcall(function() return entity.Variant end)
    return typeOk and (tonumber(sourceType) or -1) or -1,
        variantOk and (tonumber(sourceVariant) or -1) or -1
end

local function appendDamageEvent(entity, amount, flags, source)
    local player = Isaac.GetPlayer(0)
    if not entity or not entity:ToPlayer() or not player or entity.Index ~= player.Index then return end
    damageEventSequence = damageEventSequence + 1
    local sourceType, sourceVariant = sourceMetadata(source)
    table.insert(damageEvents, {
        id = damageEventSequence,
        frame = game:GetFrameCount(),
        amount = tonumber(amount) or 0,
        flags = tonumber(flags) or 0,
        source_type = sourceType,
        source_variant = sourceVariant,
    })
    while #damageEvents > damageEventLimit do table.remove(damageEvents, 1) end
end

local function resetRunObservations()
    roomVisitSequence = 0
    roomEnteredFrame = -1
    roomClearedFrame = -1
    lastEnemyCount = 0
    damageEvents = {}
    bombTargetId, bombPlaced, bombPosition, bombRoomKey = -1, false, nil, ""
    bombEntity = nil
    bombPlacementDistance = -1
    bombPlacedFrame = -1
    bombRetreatDirection = Vector(1, 0)
    bombRetreatActive = false
    ghostBombRetreatActive = false
    bombedWallKeys = {}
    bombError = nil
    nativeSeenTears = {}
    nativeTearFrame, nativeFireStartFrame = -10000, -1
    hazardLaneRoomKey, hazardLaneTargetId, hazardLaneAxis = "", -1, ""
end

local function vectorTable(v)
    return { x = math.floor(v.X * 10 + 0.5) / 10, y = math.floor(v.Y * 10 + 0.5) / 10 }
end

local function actualDoorPosition(room, slot)
    local fallback = room:GetDoorSlotPosition(slot)
    local door = room:GetDoor(slot)
    if door then
        local ok, position = pcall(function() return door.Position end)
        if ok and position and position.X and position.Y and position:Distance(fallback) < 180 then
            return position
        end
    end
    return fallback
end

local function doorSlotDirection(slot)
    -- DoorSlot uses the stable order LEFT, UP, RIGHT, DOWN for each door
    -- index. Some room shapes expose a misleading GridEntityDoor.Position;
    -- the slot direction remains reliable for ordinary door input.
    local side = slot % 4
    if side == 0 then return Vector(-1, 0) end
    if side == 1 then return Vector(0, -1) end
    if side == 2 then return Vector(1, 0) end
    return Vector(0, 1)
end

local function entityTable(entity)
    local telegraph = ""
    local spriteOk, sprite = pcall(function() return entity:GetSprite() end)
    if spriteOk and sprite then
        local animationOk, animation = pcall(function() return sprite:GetAnimation() end)
        if animationOk then telegraph = tostring(animation or "") end
    end
    local state = -1
    local npc = entity:ToNPC()
    local isBoss = false
    if npc then
        local stateOk, npcState = pcall(function() return npc.State end)
        if stateOk and npcState then state = tonumber(npcState) or -1 end
        local bossOk, boss = pcall(function() return npc:IsBoss() end)
        isBoss = bossOk and boss == true
    end
    return {
        id = entity.Index,
        type = entity.Type,
        pos = vectorTable(entity.Position),
        vel = vectorTable(entity.Velocity),
        hp = entity.HitPoints or 0,
        variant = entity.Variant or -1,
        subtype = entity.SubType or -1,
        state = state,
        telegraph = telegraph,
        is_boss = isBoss,
        grid_index = game:GetRoom():GetGridIndex(entity.Position),
    }
end

-- Fireplaces and poop are not hostile NPCs, but they still block the room
-- exit. Keep them as a separate observation class so room:IsClear() cannot
-- accidentally authorize a door while one is still present.
local FIREPLACE_TYPE = EntityType.ENTITY_FIREPLACE or -1
local POOP_TYPE = EntityType.ENTITY_POOP or -1
-- Type 33 contains ordinary, red, blue and other fireplace variants. Blue
-- fire is invulnerable to tears; only the explicit bomb policy may target it.
local BLUE_FIRE_VARIANTS = { [2] = true, [12] = true }
local PURPLE_FIRE_VARIANTS = { [3] = true, [13] = true }
local GRID_FIREPLACE_TYPE = (GridEntityType and GridEntityType.GRID_FIREPLACE) or -1
local GRID_POOP_TYPE = (GridEntityType and GridEntityType.GRID_POOP) or -1
-- Tinted/X rocks are the only rocks that are intentionally bomb targets.
-- Ordinary rocks remain absent from the hazard stream and never block exits.
local GRID_TINTED_ROCK_TYPE = (GridEntityType and GridEntityType.GRID_ROCKT) or -1
local GRID_SUPER_TINTED_ROCK_TYPE = (GridEntityType and GridEntityType.GRID_ROCK_SS) or -1
local GRID_TRAPDOOR_TYPE = (GridEntityType and GridEntityType.GRID_TRAPDOOR) or -1
local GRID_SPIKES_TYPE = (GridEntityType and GridEntityType.GRID_SPIKES) or -1
local GRID_SPIKES_ONOFF_TYPE = (GridEntityType and GridEntityType.GRID_SPIKES_ONOFF) or -1
local GRID_PRESSURE_PLATE_TYPE = (GridEntityType and GridEntityType.GRID_PRESSURE_PLATE) or -1
local GRID_TNT_TYPE = (GridEntityType and GridEntityType.GRID_TNT) or -1

local function gridState(grid)
    local ok, state = pcall(function() return grid.State end)
    return ok and tonumber(state) or nil
end

local function redPoopGrid(grid)
    if not grid or grid:GetType() ~= GRID_POOP_TYPE then return false end
    local ok, variant = pcall(function() return grid:GetVariant() end)
    return ok and tonumber(variant) == 1
end

local function gridEvent(grid, index)
    if not grid then return nil end
    local kind = nil
    local gridType = grid:GetType()
    if gridType == GRID_SPIKES_TYPE or gridType == GRID_SPIKES_ONOFF_TYPE then kind = "spike"
    elseif gridType == GRID_PRESSURE_PLATE_TYPE then kind = "button"
    elseif gridType == GRID_TNT_TYPE then kind = "tnt" end
    if not kind then return nil end
    local state = gridState(grid)
    local active = false
    local triggered = false
    if kind == "spike" then
        -- SpikesOnOff enum is ON=0, OFF=1 (Repentance's SPIKES_ONOFF). The old generic
        -- `state ~= 0` check inverted this room hazard and let pickup paths
        -- cross active spike clusters. Ordinary SPIKES stay dangerous unless
        -- the engine explicitly reports no collision.
        local collisionOk, collision = pcall(function() return grid.CollisionClass end)
        local collidable = not collisionOk or tonumber(collision) ~= 0
        if gridType == GRID_SPIKES_ONOFF_TYPE then
            active = collidable and (state == nil or state == 0)
        else
            active = collidable
        end
    elseif kind == "button" then
        -- Repentance pressure plates use state 3 (trigger) or 4 (reward)
        -- after being pressed. State 1/2 are still pending transitions.
        triggered = state ~= nil and state >= 3
        active = not triggered
    elseif kind == "tnt" then
        local collisionOk, collision = pcall(function() return grid.CollisionClass end)
        active = (state == nil or state < 2) and (not collisionOk or tonumber(collision) ~= 0)
    end
    return { kind = kind, id = -100000 - index, pos = vectorTable(grid.Position),
        grid_index = index, state = state or -1, active = active, triggered = triggered }
end

local function currentDimension(level)
    local descriptor = level:GetCurrentRoomDesc()
    if not descriptor or not GetPtrHash then return 0 end
    local okIndex, safeIndex = pcall(function() return descriptor.SafeGridIndex end)
    if not okIndex or safeIndex == nil then return 0 end
    for dimension = 0, 2 do
        local ok, same = pcall(function()
            local other = level:GetRoomByIdx(safeIndex, dimension)
            return other and GetPtrHash(descriptor) == GetPtrHash(other)
        end)
        if ok and same then return dimension end
    end
    return 0
end

local function currentRoomKey()
    local level = game:GetLevel()
    return table.concat({ tostring(startSeed()), tostring(level:GetStage()),
        tostring(level:GetStageType()), tostring(currentDimension(level)),
        tostring(level:GetCurrentRoomIndex()) }, ":")
end

local function bombStillLive()
    if not bombPlaced or bombRoomKey ~= currentRoomKey()
        or game:GetFrameCount() - bombPlacedFrame >= 120 then return false end
    if game:GetFrameCount() - bombPlacedFrame < 2 then return true end
    local ok, exists = pcall(function() return bombEntity and bombEntity:Exists() end)
    return ok and exists == true
end

local function weaponKind(player)
    if not WeaponType then return "unknown", false end
    local kinds = {
        { "WEAPON_BRIMSTONE", "brimstone" }, { "WEAPON_LASER", "laser" },
        { "WEAPON_KNIFE", "knife" }, { "WEAPON_BOMBS", "bombs" },
        { "WEAPON_ROCKETS", "rockets" }, { "WEAPON_MONSTROS_LUNGS", "monstros_lungs" },
        { "WEAPON_LUDOVICO_TECHNIQUE", "ludovico" }, { "WEAPON_TECH_X", "tech_x" },
        { "WEAPON_BONE", "bone" }, { "WEAPON_SPIRIT_SWORD", "spirit_sword" },
    }
    for _, entry in ipairs(kinds) do
        local value = WeaponType[entry[1]]
        if value then
            local ok, present = pcall(function() return player:HasWeaponType(value) end)
            if ok and present then return entry[2], true end
        end
    end
    local tears = WeaponType.WEAPON_TEARS
    if tears then
        local ok, present = pcall(function() return player:HasWeaponType(tears) end)
        if ok and present then return "tear", true end
    end
    return "unknown", false
end

local function hazardKind(entity)
    if entity.Type == FIREPLACE_TYPE then
        if BLUE_FIRE_VARIANTS[tonumber(entity.Variant) or -1] then return "blue_fire" end
        if PURPLE_FIRE_VARIANTS[tonumber(entity.Variant) or -1] then return "purple_fire" end
        return "fire"
    end
    if entity.Type == POOP_TYPE then return "poop" end
    return nil
end

local function trackingBombInfo(entity, player)
    -- Enemy bombs and the ghost effects they spawn are not ordinary room
    -- hazards: they close on Isaac and require an immediate escape. Never
    -- classify the bomb placed by this controller as hostile.
    if not entity or not player or entity.Index == (bombEntity and bombEntity.Index or -1) then return nil end
    local entityType = entity.Type
    local isBomb = entityType == (EntityType.ENTITY_BOMB or 4)
    if not isBomb and entityType ~= (EntityType.ENTITY_EFFECT or 1000) then return nil end
    local ownerOk, owner = pcall(function() return entity.SpawnerEntity end)
    if ownerOk and owner and owner.Index == player.Index then return nil end
    local parentOk, parent = pcall(function() return entity.Parent end)
    if parentOk and parent and parent.Index == player.Index then return nil end
    local animation = ""
    local spriteOk, sprite = pcall(function() return entity:GetSprite() end)
    if spriteOk and sprite then
        local animationOk, current = pcall(function() return sprite:GetAnimation() end)
        if animationOk then animation = string.lower(tostring(current or "")) end
    end
    local ghostAnimation = string.find(animation, "ghost", 1, true)
        or string.find(animation, "homing", 1, true)
        or string.find(animation, "chase", 1, true)
        or string.find(animation, "follow", 1, true)
    if not isBomb and not ghostAnimation then return nil end
    local delta = player.Position - entity.Position
    local distance = delta:Length()
    local velocity = entity.Velocity or Vector(0, 0)
    local closing = delta.X * velocity.X + delta.Y * velocity.Y > 0.25
    -- A non-player bomb is only promoted when it is actually moving toward
    -- Isaac. Ghost effects with a recognizable animation use the same test,
    -- which avoids treating decorative or expired effects as threats.
    if not closing or distance > 300 then return nil end
    local radius = math.max(34, math.min(62, (tonumber(entity.Size) or 20) + (tonumber(player.Size) or 10) + 18))
    return {
        id = entity.Index, kind = "ghost_bomb", type = entityType,
        pos = vectorTable(entity.Position), vel = vectorTable(velocity),
        radius = radius, variant = entity.Variant or -1, subtype = entity.SubType or -1,
        animation = animation, state = -1,
    }
end

local function nearestTrackingBomb(player)
    local nearest, nearestDistance = nil, nil
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local threat = trackingBombInfo(entity, player)
        if threat then
            local distance = entity.Position:Distance(player.Position)
            if not nearestDistance or distance < nearestDistance then
                nearest, nearestDistance = threat, distance
            end
        end
    end
    return nearest
end

local function bombOnlyFireKind(kind)
    return kind == "blue_fire" or kind == "purple_fire"
end

local function isMovingSpikeTrap(entity)
    -- Poky/Slide share one entity type; Wall Hugger is another. Both can be
    -- reported as active NPCs despite being invulnerable room machinery.
    return entity.Type == (EntityType.ENTITY_POKY or 44)
        or entity.Type == (EntityType.ENTITY_WALL_HUGGER or 218)
end

local function isStoneTrap(entity)
    return entity.Type == (EntityType.ENTITY_STONEHEAD or 42)
        or entity.Type == (EntityType.ENTITY_STONE_EYE or 201)
        or entity.Type == (EntityType.ENTITY_CONSTANT_STONE_SHOOTER or 202)
end

local function liveHazardKind(entity)
    local kind = hazardKind(entity)
    if not kind then return nil end
    local npc = entity:ToNPC()
    if npc then
        -- Fireplaces are not hostile NPCs on all Repentance builds, so
        -- IsActiveEnemy alone cannot be used as a whitelist. Use the full
        -- lifecycle below (dead/HP/sprite) and only reject an explicitly
        -- inactive object when the API reports that signal.
        local activeOk, active = pcall(function() return npc:IsActive() end)
        local activeEnemyOk, activeEnemy = pcall(function() return npc:IsActiveEnemy(false) end)
        if activeOk and not active and activeEnemyOk and not activeEnemy then return nil end
        local deadOk, dead = pcall(function() return npc:IsDead() end)
        if deadOk and dead then return nil end
        local hpOk, hp = pcall(function() return entity.HitPoints end)
        if hpOk and hp and hp <= 0 then return nil end

        -- Repentance builds use several names for the post-hit fireplace
        -- animation. They can still report IsActive for a few frames, so
        -- explicitly exclude those visual lifecycle states as well.
        local spriteOk, sprite = pcall(function() return entity:GetSprite() end)
        if spriteOk and sprite then
            local animationOk, animation = pcall(function() return sprite:GetAnimation() end)
            local name = animationOk and string.lower(tostring(animation or "")) or ""
            if string.find(name, "death", 1, true)
                or string.find(name, "destroy", 1, true)
                or string.find(name, "poof", 1, true)
                or string.find(name, "dissapear", 1, true)
                or string.find(name, "disappear", 1, true)
                or string.find(name, "extingu", 1, true)
                or string.find(name, "off", 1, true)
                or string.find(name, "nofire", 1, true)
                or string.find(name, "no_fire", 1, true)
                or string.find(name, "unlit", 1, true)
            then
                return nil
            end
            for _, animationName in ipairs({ "Death", "Destroy", "Poof", "Dissapear", "Dissapear2", "Dissapear3", "Disappear", "Disappear2", "Disappear3", "Extinguish", "Off", "NoFire", "NoFire2", "Unlit" }) do
                local finishedOk, finished = pcall(function() return sprite:IsFinished(animationName) end)
                local playingOk, playing = pcall(function() return sprite:IsPlaying(animationName) end)
                if (finishedOk and finished) or (playingOk and playing) then return nil end
            end
        end
    end
    return kind
end

local function gridHazardKind(grid)
    if not grid then return nil end
    local gridType = grid:GetType()
    if gridType == GRID_FIREPLACE_TYPE then
        local ok, variant = pcall(function() return grid:GetVariant() end)
        variant = ok and tonumber(variant) or -1
        if PURPLE_FIRE_VARIANTS[variant] then return "purple_fire" end
        if BLUE_FIRE_VARIANTS[variant] then return "blue_fire" end
        return "fire"
    end
    if gridType == GRID_POOP_TYPE and not redPoopGrid(grid) then return "poop" end
    if gridType == GRID_TINTED_ROCK_TYPE or gridType == GRID_SUPER_TINTED_ROCK_TYPE then return "xrock" end
    return nil
end

local function liveGridHazardKind(grid)
    local kind = gridHazardKind(grid)
    if not kind then return nil end
    local collisionOk, collision = pcall(function() return grid.CollisionClass end)
    -- Repentance exposes this as an integer on some builds and an enum value
    -- on others. Zero is COLLISION_NONE in both representations.
    if collisionOk and tonumber(collision) == 0 then return nil end
    local spriteOk, sprite = pcall(function() return grid:GetSprite() end)
    if spriteOk and sprite then
        local animationOk, animation = pcall(function() return sprite:GetAnimation() end)
        local name = animationOk and string.lower(tostring(animation or "")) or ""
        if (kind == "fire" or bombOnlyFireKind(kind)) and (string.find(name, "dissapear", 1, true)
            or string.find(name, "disappear", 1, true)) then return nil end
        for _, animation in ipairs({ "Death", "Destroy", "Poof", "NoFire", "NoFire2", "Unlit", "Off" }) do
            local finishedOk, finished = pcall(function() return sprite:IsFinished(animation) end)
            local playingOk, playing = pcall(function() return sprite:IsPlaying(animation) end)
            if (finishedOk and finished) or (playingOk and playing) then return nil end
        end
    end
    return kind
end

local function hazardTable(entity, kind)
    local spriteName = ""
    local npcState = -1
    local spriteOk, sprite = pcall(function() return entity:GetSprite() end)
    if spriteOk and sprite then
        local animationOk, animation = pcall(function() return sprite:GetAnimation() end)
        if animationOk then spriteName = tostring(animation or "") end
    end
    local npc = entity:ToNPC()
    if npc then
        local stateOk, state = pcall(function() return npc.State end)
        if stateOk and state then npcState = tonumber(state) or -1 end
    end
    return {
        id = entity.Index, type = entity.Type, kind = kind,
        pos = vectorTable(entity.Position), vel = vectorTable(entity.Velocity),
        grid_index = game:GetRoom():GetGridIndex(entity.Position),
        hp = entity.HitPoints or 0, destructible = true, animation = spriteName,
        requires_bomb = bombOnlyFireKind(kind),
        variant = entity.Variant or -1, subtype = entity.SubType or -1, state = npcState,
        telegraph = spriteName,
    }
end

local function gridHazardTable(grid, gridIndex, kind)
    local animation = ""
    local variantOk, variant = pcall(function() return grid:GetVariant() end)
    variant = variantOk and tonumber(variant) or -1
    local spriteOk, sprite = pcall(function() return grid:GetSprite() end)
    if spriteOk and sprite then
        local animationOk, current = pcall(function() return sprite:GetAnimation() end)
        if animationOk then animation = tostring(current or "") end
    end
    return {
        id = -100000 - gridIndex, type = grid:GetType(), kind = kind,
        pos = vectorTable(grid.Position), vel = { x = 0, y = 0 },
        hp = 0, destructible = true, requires_bomb = kind == "xrock" or bombOnlyFireKind(kind), grid_index = gridIndex, animation = animation,
        variant = variant,
    }
end

local function ignoredPickup(id)
    for _, value in ipairs(action.ignoredPickupIds or {}) do
        if tonumber(value) == id then return true end
    end
    return false
end

local function collectLayout(room, level)
    local descriptor = level:GetCurrentRoomDesc()
    local roomIndex = level:GetCurrentRoomIndex()
    local blocked, doors, gridEvents, dangerGridIndices, bombWalls = {}, {}, {}, {}, {}
    local function roomTypeName(data)
        if not data then return "unknown" end
        local roomType = data.Type
        local names = {}
        local function add(name, label)
            local value = RoomType[name]
            if value ~= nil then names[value] = label end
        end
        add("ROOM_DEFAULT", "default")
        add("ROOM_SHOP", "shop")
        add("ROOM_TREASURE", "treasure")
        add("ROOM_BOSS", "boss")
        add("ROOM_SECRET", "secret")
        add("ROOM_SUPERSECRET", "super_secret")
        add("ROOM_CURSE", "curse")
        add("ROOM_SACRIFICE", "sacrifice")
        add("ROOM_CHALLENGE", "challenge")
        add("ROOM_LIBRARY", "library")
        return names[roomType] or "special"
    end
    for index = 0, room:GetGridSize() - 1 do
        if room:GetGridPath(index) >= 1000 then table.insert(blocked, index) end
        local grid = room:GetGridEntity(index)
        local event = gridEvent(grid, index)
        if event then
            table.insert(gridEvents, event)
            if event.kind == "spike" and event.active then table.insert(dangerGridIndices, index) end
            if event.kind == "tnt" and event.active then table.insert(dangerGridIndices, index) end
        end
        local gridHazard = liveGridHazardKind(grid)
        if gridHazard == "fire" or bombOnlyFireKind(gridHazard) or redPoopGrid(grid) then table.insert(dangerGridIndices, index) end
    end
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then
            local targetIndex = door.TargetRoomIndex or -1
            local target = targetIndex >= 0 and level:GetRoomByIdx(targetIndex) or nil
            local targetData = target and target.Data or nil
            local lockKnown, locked = false, false
            local lockOk, lockValue = pcall(function() return door:IsLocked() end)
            if lockOk and type(lockValue) == "boolean" then lockKnown, locked = true, lockValue end
            local openKnown, open = false, false
            local openOk, openValue = pcall(function() return door:IsOpen() end)
            if openOk and type(openValue) == "boolean" then openKnown, open = true, openValue end
            table.insert(doors, {
                slot = slot,
                pos = vectorTable(actualDoorPosition(room, slot)),
                target_room_index = targetIndex,
                target_is_boss = targetData and targetData.Type == RoomType.ROOM_BOSS or false,
                target_clear = target and target.Clear or false,
                target_room_type = roomTypeName(targetData),
                door_locked = locked,
                door_lock_known = lockKnown,
                door_open = open,
                door_open_known = openKnown,
                grid_index = room:GetGridIndex(actualDoorPosition(room, slot)),
            })
        end
    end
    -- Only infer neighboring hidden rooms for 1x1 rooms; larger room shapes
    -- need shape-specific grid offsets and are deliberately skipped.
    if room:GetRoomShape() == RoomShape.ROOMSHAPE_1x1 then
        local offsets = { -1, -13, 1, 13 }
        local dimension = currentDimension(level)
        for slot = 0, 3 do
            local targetIndex = roomIndex + offsets[slot + 1]
            local sameRow = slot ~= 0 and slot ~= 2 or math.floor(roomIndex / 13) == math.floor(targetIndex / 13)
            if targetIndex >= 0 and targetIndex < 169 and sameRow and room:IsDoorSlotAllowed(slot) then
                local target = level:GetRoomByIdx(targetIndex, dimension)
                local targetType = target and target.Data and target.Data.Type or -1
                if targetType == RoomType.ROOM_SECRET or targetType == RoomType.ROOM_SUPERSECRET then
                    local door = room:GetDoor(slot)
                    local open = door and door:IsOpen()
                    local position = actualDoorPosition(room, slot)
                    local inward = room:GetCenterPos() - position
                    if inward:Length() > 0 then
                        local site = position + inward:Normalized() * 60
                        local siteIndex = room:GetGridIndex(site)
                        if not open and room:IsPositionInRoom(site, 12) and room:GetGridPath(siteIndex) < 1000 then
                            table.insert(bombWalls, { slot = slot, pos = vectorTable(position), site = vectorTable(site),
                                grid_index = siteIndex, room_type = targetType == RoomType.ROOM_SECRET and "secret" or "super_secret",
                                bombed = bombedWallKeys[currentRoomKey() .. ":" .. tostring(slot)] == true })
                        end
                    end
                end
            end
        end
    end
    return {
        room_index = roomIndex, room_type = roomTypeName(descriptor.Data),
        is_boss = descriptor.Data and descriptor.Data.Type == RoomType.ROOM_BOSS or false,
        grid_width = room:GetGridWidth(), grid_height = room:GetGridHeight(), blocked = blocked, doors = doors,
        grid_events = gridEvents, danger_grid_indices = dangerGridIndices, bomb_walls = bombWalls,
    }
end

local function pickupTable(entity)
    local pickup = entity:ToPickup()
    local collectible = entity.Variant == PickupVariant.PICKUP_COLLECTIBLE
    -- After a collectible is taken, Repentance can leave the stone pedestal as
    -- an ENTITY_PICKUP with subtype 0 for several frames. It is scenery, not a
    -- second item target, so never expose it to Python navigation.
    if collectible and (tonumber(entity.SubType) or 0) <= 0 then return nil end
    local quality, name, kind = 0, "pickup", "other"
    local function variant(name)
        return PickupVariant[name]
    end
    local chestNames = {
        PICKUP_CHEST = "chest",
        PICKUP_LOCKEDCHEST = "locked_chest",
        PICKUP_REDCHEST = "red_chest",
        PICKUP_BOMBCHEST = "bomb_chest",
        PICKUP_SPIKED_CHEST = "spiked_chest",
        PICKUP_SPIKEDCHEST = "spiked_chest",
        PICKUP_ETERNALCHEST = "eternal_chest",
        PICKUP_MIMICCHEST = "mimic_chest",
        PICKUP_OLDCHEST = "old_chest",
        PICKUP_WOODENCHEST = "wooden_chest",
        PICKUP_HAUNTEDCHEST = "haunted_chest",
    }
    for variantName, chestKind in pairs(chestNames) do
        local chestVariant = variant(variantName)
        if chestVariant and entity.Variant == chestVariant then
            kind, name = chestKind, chestKind
            collectible = true
            quality = 1
            break
        end
    end
    if collectible and kind == "other" then
        kind = "collectible"
        local config = Isaac.GetItemConfig():GetCollectible(entity.SubType)
        if config then
            quality = config.Quality or 0
            name = config.Name or "collectible"
        end
    elseif entity.Variant == PickupVariant.PICKUP_KEY then
        kind, name = "key", "key"
    elseif entity.Variant == PickupVariant.PICKUP_COIN then
        kind, name = "coin", "coin"
    elseif entity.Variant == PickupVariant.PICKUP_BOMB then
        kind, name = "bomb", "bomb"
    elseif entity.Variant == PickupVariant.PICKUP_HEART then
        local subtype = entity.SubType
        local full = HeartSubType and HeartSubType.HEART_FULL or 1
        local half = HeartSubType and HeartSubType.HEART_HALF or 2
        local soul = HeartSubType and HeartSubType.HEART_SOUL or 3
        local eternal = HeartSubType and HeartSubType.HEART_ETERNAL or 4
        local double = HeartSubType and HeartSubType.HEART_DOUBLEPACK or 5
        local black = HeartSubType and HeartSubType.HEART_BLACK or 6
        local golden = HeartSubType and HeartSubType.HEART_GOLDEN or 7
        local halfSoul = HeartSubType and HeartSubType.HEART_HALF_SOUL or 8
        local scared = HeartSubType and HeartSubType.HEART_SCARED or 9
        local blended = HeartSubType and HeartSubType.HEART_BLENDED or 10
        local bone = HeartSubType and HeartSubType.HEART_BONE or 11
        local rotten = HeartSubType and HeartSubType.HEART_ROTTEN or 12
        if subtype == soul then kind, name = "soul_heart", "soul heart"
        elseif subtype == black then kind, name = "black_heart", "black heart"
        elseif subtype == eternal then kind, name = "eternal_heart", "eternal heart"
        elseif subtype == golden then kind, name = "golden_heart", "golden heart"
        elseif subtype == bone then kind, name = "bone_heart", "bone heart"
        elseif subtype == halfSoul then kind, name = "half_soul_heart", "half soul heart"
        elseif subtype == scared then kind, name = "scared_heart", "scared heart"
        elseif subtype == blended then kind, name = "blended_heart", "blended heart"
        elseif subtype == rotten then kind, name = "rotten_heart", "rotten heart"
        elseif subtype == half then kind, name = "red_half_heart", "half red heart"
        elseif subtype == double then kind, name = "red_double_heart", "double red heart"
        elseif subtype == full then kind, name = "red_heart", "red heart"
        else kind, name = "heart", "heart" end
    elseif ((variant("PICKUP_CARD") and entity.Variant == variant("PICKUP_CARD")) or (variant("PICKUP_TAROTCARD") and entity.Variant == variant("PICKUP_TAROTCARD"))) then
        kind, name = "card", "card"
    elseif variant("PICKUP_PILL") and entity.Variant == variant("PICKUP_PILL") then
        kind, name = "pill", "pill"
    elseif variant("PICKUP_GRAB_BAG") and entity.Variant == variant("PICKUP_GRAB_BAG") then
        kind, name = "grab_bag", "grab bag"
    elseif variant("PICKUP_TRINKET") and entity.Variant == variant("PICKUP_TRINKET") then
        kind, name = "trinket", "trinket"
        local config = Isaac.GetItemConfig():GetTrinket(entity.SubType)
        if config and config.Name then name = config.Name end
    end
    return { id = entity.Index, pos = vectorTable(entity.Position), grid_index = game:GetRoom():GetGridIndex(entity.Position), subtype = entity.SubType, price = pickup.Price or 0,
        quality = quality, name = name, kind = kind, is_collectible = collectible }
end

local function isCombatEnemy(entity)
    -- Fireplaces/poop have NPC-like entities on some rooms, but they are
    -- obstacles, never combat targets. Keep them in the hazard channel even
    -- when the engine reports them as active enemies.
    if hazardKind(entity) or isMovingSpikeTrap(entity) or isStoneTrap(entity)
        or trackingBombInfo(entity, Isaac.GetPlayer(0)) then return false end
    local npc = entity:ToNPC()
    -- IsVulnerableEnemy also includes several non-hostile NPCs (for example
    -- props and friendly entities). Only active, non-friendly hostile NPCs
    -- may keep the room in combat or influence aim/navigation.
    -- X rocks can release spiders into a room whose native clear flag stays
    -- true. Keep this specific hostile type even if IsActiveEnemy lags behind.
    return npc and (npc:IsActiveEnemy(false) or entity.Type == EntityType.ENTITY_SPIDER)
        and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
        and entity.HitPoints > 0
end

local function hasCombatEnemy()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if isCombatEnemy(entity) then return true end
    end
    return false
end

local function bossExitInfo(room)
    if not room:IsClear() or GRID_TRAPDOOR_TYPE < 0 then
        return false, { x = 0, y = 0 }, -1
    end
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        if grid then
            local ok, gridType = pcall(function() return grid:GetType() end)
            if ok and gridType == GRID_TRAPDOOR_TYPE then
                return true, vectorTable(grid.Position), index
            end
        end
    end
    return false, { x = 0, y = 0 }, -1
end

local function dangerousCreep(entity)
    if entity.Type ~= EntityType.ENTITY_EFFECT then return false end
    local variant = entity.Variant
    local hostile = variant == EffectVariant.CREEP_RED or variant == EffectVariant.CREEP_GREEN
        or variant == EffectVariant.CREEP_YELLOW or variant == EffectVariant.CREEP_BLACK
        or variant == EffectVariant.CREEP_BROWN
    if not hostile then return false end
    local ok, friendly = pcall(function() return EntityEffect.IsPlayerCreep(variant) end)
    return not (ok and friendly)
end

local function playerIsDead(player)
    local ok, dead = pcall(function() return player:IsDead() end)
    if ok and dead then return true end
    return (player:GetHearts() + player:GetSoulHearts() + player:GetBoneHearts() * 2) <= 0
end

local function handleDeathAndRestart(player)
    if not playerIsDead(player) then
        if restartPhase ~= "alive" then
            restartPhase = "alive"
            deathDetectedFrame = -1
            deathWaitTicks = 0
            restartAttempted = false
            restartError = nil
            automatic = not manualOverride
            lastStateFrame = -10000
            lastLayoutRoom = -99999
            lastLayout = nil
            lastObservedRoomIndex = -99999
            lastPlayerPosition = nil
            lastTransitionSourceRoomIndex = -1
            lastTransitionTargetRoomIndex = -1
            roomEntryFrame = -10000
            action = { id = "", move = Vector(0, 0), shoot = Vector(0, 0), mode = "wait", target = "", reason = "new run starting", sourceRoomIndex = -1 }
            lastActionFrame = -10000
            resetRunObservations()
            lastUsedPill = {}
            pillUseResult = "idle"
            lastTrinketSwapTarget = -1
            trinketSwapResult = "idle"
        end
        return false
    end
    if deathDetectedFrame < 0 then
        deathDetectedFrame = game:GetFrameCount()
        deathWaitTicks = 0
        restartPhase = "death_wait"
        restartAttempted = false
        restartError = nil
        automatic = false
        action = { id = "dead_wait", move = Vector(0, 0), shoot = Vector(0, 0), mode = "wait", target = "", reason = "dead; waiting to restart", sourceRoomIndex = -1 }
        resolvedMove = Vector(0, 0)
    end
    deathWaitTicks = deathWaitTicks + 1
    if not restartAttempted and deathWaitTicks >= 60 then
        restartAttempted = true
        restartPhase = "restarting"
        local ok, err = pcall(function()
            game:StartNewGame(false)
        end)
        if ok then
            restartCount = restartCount + 1
            restartPhase = "waiting_new_run"
            lastActionFrame = -10000
            lastStateFrame = -10000
            lastLayoutRoom = -99999
            lastLayout = nil
            lastObservedRoomIndex = -99999
            lastPlayerPosition = nil
            lastTransitionSourceRoomIndex = -1
            lastTransitionTargetRoomIndex = -1
            roomEntryFrame = -10000
            action = { id = "", move = Vector(0, 0), shoot = Vector(0, 0), mode = "wait", target = "", reason = "restart requested", sourceRoomIndex = -1 }
            resetRunObservations()
            lastUsedPill = {}
            pillUseResult = "idle"
            lastTrinketSwapTarget = -1
            trinketSwapResult = "idle"
        else
            restartError = tostring(err)
            restartPhase = "restart_error"
        end
    end
    return true
end

local function collectState()
    local player = Isaac.GetPlayer(0)
    local level, room = game:GetLevel(), game:GetRoom()
    local roomClear = room:IsClear()
    local frame = game:GetFrameCount()
    local roomIndex = level:GetCurrentRoomIndex()
    local currentWeapon, weaponKnown = weaponKind(player)
    local heldTrinkets = {}
    local trinketSlots = math.max(1, math.min(2, player:GetMaxTrinkets()))
    for slot = 0, trinketSlots - 1 do
        local id = player:GetTrinket(slot)
        if id and id ~= 0 then table.insert(heldTrinkets, id) end
    end
    local heldPills = {}
    for slot = 0, 3 do
        local color = player:GetPill(slot)
        if color and color ~= 0 then table.insert(heldPills, { slot = slot, color = color }) end
    end
    local bossExitAvailable, bossExitPosition, bossExitGridIndex = bossExitInfo(room)
    local enemies, projectiles, pickups, hazards, dangerEffects = {}, {}, {}, {}, {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local trackingBomb = trackingBombInfo(entity, player)
        if trackingBomb then
            table.insert(dangerEffects, trackingBomb)
        elseif isCombatEnemy(entity) then
            table.insert(enemies, entityTable(entity))
        elseif isMovingSpikeTrap(entity) then
            -- Moving spike blocks are a collision threat, not something tears
            -- can kill. Feed their current and near-future cells to routing.
            local radius = math.max(35, math.min(55, (tonumber(entity.Size) or 20) + (tonumber(player.Size) or 10) + 10))
            table.insert(dangerEffects, { id = entity.Index, kind = "moving_spike",
                pos = vectorTable(entity.Position), radius = radius, variant = entity.Variant })
            if entity.Velocity:Length() > 1 then
                table.insert(dangerEffects, { id = entity.Index, kind = "moving_spike_future",
                    pos = vectorTable(entity.Position + entity.Velocity * 4), radius = radius,
                    variant = entity.Variant })
            end
        elseif entity.Type == EntityType.ENTITY_PROJECTILE then
            table.insert(projectiles, entityTable(entity))
        elseif entity.Type == EntityType.ENTITY_PICKUP and entity:ToPickup() then
            local pickup = pickupTable(entity)
            if pickup then table.insert(pickups, pickup) end
        elseif dangerousCreep(entity) then
            table.insert(dangerEffects, { id = entity.Index, pos = vectorTable(entity.Position),
                radius = math.max(24, math.min(65, tonumber(entity.Size) or 28)), variant = entity.Variant })
        else
            local kind = liveHazardKind(entity)
            if kind then table.insert(hazards, hazardTable(entity, kind)) end
        end
    end
    -- Bombed rocks can spawn spiders after the engine has already marked the
    -- room clear. Live hostile entities must take priority over that flag.
    if #enemies > 0 then
        roomClear = false
        bossExitAvailable = false
    end
    if roomClear and roomClearedFrame < 0 then roomClearedFrame = frame end
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        local kind = liveGridHazardKind(grid)
        if kind then table.insert(hazards, gridHazardTable(grid, index, kind)) end
    end
    local enemyTotalHp = 0
    for _, enemy in ipairs(enemies) do enemyTotalHp = enemyTotalHp + (tonumber(enemy.hp) or 0) end
    local enemyCount = #enemies
    local enemyKillDelta = math.max(0, lastEnemyCount - enemyCount)
    lastEnemyCount = enemyCount
    local state = {
        type = "state",
        mod_version = MOD_VERSION,
        frame = frame,
        start_seed = startSeed(),
        room_visit_sequence = roomVisitSequence,
        room_entered_frame = roomEnteredFrame,
        room_cleared_frame = roomClearedFrame,
        damage_events = damageEvents,
        room_clear = roomClear,
        boss_exit_available = bossExitAvailable,
        boss_exit_position = bossExitPosition,
        boss_exit_grid_index = bossExitGridIndex,
        hostile_enemy_count = #enemies,
        enemy_count = enemyCount,
        enemy_total_hp = enemyTotalHp,
        enemy_kill_delta = enemyKillDelta,
        enemy_observation_valid = true,
        hazards_observation_valid = true,
        room_index = roomIndex,
        held_trinkets = heldTrinkets, trinket_slots = trinketSlots,
        held_pills = heldPills, pill_use_result = pillUseResult,
        trinket_swap_result = trinketSwapResult,
        stage = level:GetStage(), stage_type = level:GetStageType(), dimension = currentDimension(level),
        transition_phase = transitionPhase,
        transition_attempt = transitionAttempt,
        transition_error = transitionError or "",
        transition_gate = transitionGate,
        transition_door_distance = transitionDoorDistance,
        last_transition_source_room_index = lastTransitionSourceRoomIndex,
        last_transition_target_room_index = lastTransitionTargetRoomIndex,
        room_entry_age_frames = math.max(0, game:GetFrameCount() - roomEntryFrame),
        backtrack_guard_active = game:GetFrameCount() - roomEntryFrame < backtrackGuardFrames,
        player_dead = playerIsDead(player),
        restart_phase = restartPhase,
        restart_count = restartCount,
        restart_error = restartError or "",
        requested_move = vectorTable(lastRequestedMove),
        resolved_move = vectorTable(lastResolvedMove),
        movement_progress = lastMovementProgress,
        movement_blocked = lastMovementBlocked,
        move_resolution_reason = lastMoveResolutionReason,
        last_action_id = action.id or "",
        last_action_mode = action.mode or "",
        last_action_sequence = currentActionSequence,
        action_age_frames = math.max(0, frame - lastActionFrame),
        bomb_placed = bombPlaced and bombRoomKey == currentRoomKey(),
        bomb_active = bombStillLive(),
        bomb_target_id = bombTargetId,
        bomb_position = bombPosition and vectorTable(bombPosition) or { x = 0, y = 0 },
        bomb_placed_frame = bombPlacedFrame,
        bomb_placement_distance = bombPlacementDistance,
        bomb_escape_direction = vectorTable(bombRetreatDirection),
        bomb_error = bombError or "",
        coins = player:GetNumCoins(), keys = player:GetNumKeys(), bombs = player:GetNumBombs(), player_grid_index = room:GetGridIndex(player.Position),
        player = {
            id = player.Index,
            type = player.Type,
            pos = vectorTable(player.Position),
            vel = vectorTable(player.Velocity),
            hp = player:GetHearts() + player:GetSoulHearts() + player:GetBoneHearts() * 2,
            red_hearts = player:GetHearts(),
            max_hearts = player:GetMaxHearts(),
            soul_hearts = player:GetSoulHearts(),
            black_hearts = player:GetBlackHearts(),
            bone_hearts = player:GetBoneHearts(),
            eternal_hearts = player:GetEternalHearts(),
            tear_range = player.TearRange,
            tear_speed = player.ShotSpeed,
            weapon_type = currentWeapon,
            weapon_type_known = weaponKnown,
        },
        enemies = enemies, projectiles = projectiles, pickups = pickups, hazards = hazards,
        danger_effects = dangerEffects,
        fired_tears = firedTearCount, fire_error = fireError,
        fire_block_reason = fireBlockReason,
    }
    -- Grid events and door state can change between packets.
    lastLayout = collectLayout(room, level)
    lastLayoutRoom = roomIndex
    local dangerousIndices = {}
    for _, index in ipairs(lastLayout.danger_grid_indices) do dangerousIndices[index] = true end
    for _, effect in ipairs(dangerEffects) do
        if effect.kind ~= "ghost_bomb" then
        local center = Vector(effect.pos.x, effect.pos.y)
        for index = 0, room:GetGridSize() - 1 do
            if room:GetGridPosition(index):Distance(center) <= effect.radius + 18 then
                dangerousIndices[index] = true
            end
        end
        end
    end
    lastLayout.danger_grid_indices = {}
    for index in pairs(dangerousIndices) do table.insert(lastLayout.danger_grid_indices, index) end
    -- Layout is cached because it is relatively expensive to build, but it
    -- must still be present in every state packet. Omitting it between the
    -- refresh frames makes Python fall back to an empty layout and emit
    -- wait_for_exit with a zero movement vector.
    state.layout = lastLayout
    return state
end

local function localFireDirection(player)
    local nearest, distance = nil, nil
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if isCombatEnemy(entity) then
            local currentDistance = entity.Position:Distance(player.Position)
            if not distance or currentDistance < distance then
                nearest, distance = entity, currentDistance
            end
        end
    end
    if not nearest then
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if liveHazardKind(entity) then
                local currentDistance = entity.Position:Distance(player.Position)
                if not distance or currentDistance < distance then
                    nearest, distance = entity, currentDistance
                end
            end
        end
    end
    if not nearest then
        local room = game:GetRoom()
        for index = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(index)
            if liveGridHazardKind(grid) then
                local currentDistance = grid.Position:Distance(player.Position)
                if not distance or currentDistance < distance then
                    nearest, distance = grid, currentDistance
                end
            end
        end
    end
    if not nearest then
        return Vector(0, 0)
    end
    -- Lead moving targets by the time a tear needs to cross the current
    -- distance. Keep the lead bounded so a reversing enemy is not over-shot.
    local velocity = Vector(0, 0)
    local velocityOk, nearestVelocity = pcall(function() return nearest.Velocity end)
    if velocityOk and nearestVelocity then velocity = nearestVelocity end
    local distance = nearest.Position:Distance(player.Position)
    local tearSpeed = math.max(1, (player.ShotSpeed or 1) * 10)
    local leadFrames = math.min(12, math.max(1.5, distance / tearSpeed))
    local predicted = nearest.Position + velocity * leadFrames
    local delta = predicted - player.Position
    if math.abs(delta.X) >= math.abs(delta.Y) then
        return Vector(delta.X >= 0 and 1 or -1, 0)
    end
    return Vector(0, delta.Y >= 0 and 1 or -1)
end

local function safeMoveCandidate(player, candidate, allowDoorThreshold, plannedBombRetreat)
    if candidate:Length() < 0.5 then return false, "zero_direction" end
    local room = game:GetRoom()
    local nextPosition = player.Position + candidate * 28
    local gridIndex = room:GetGridIndex(nextPosition)
    if not allowDoorThreshold and room:GetGridPath(gridIndex) >= 1000 then return false, "grid_wall" end
    for _, point in ipairs({ player.Position + candidate * 14, nextPosition }) do
        for _, offset in ipairs({ Vector(0, 0), Vector(16, 0), Vector(-16, 0),
            Vector(0, 16), Vector(0, -16) }) do
            local sampled = point + offset
            local index = room:GetGridIndex(sampled)
            local event = gridEvent(room:GetGridEntity(index), index)
            local redPoop = room:GetGridEntity(index)
            if redPoopGrid(redPoop) and sampled:Distance(redPoop.Position) < 43
                and nextPosition:Distance(redPoop.Position) <= player.Position:Distance(redPoop.Position)
            then return false, "red_poop" end
            local eventPosition = event and Vector(event.pos.x, event.pos.y) or nil
            if event and event.active and (event.kind == "spike" or event.kind == "tnt")
                and sampled:Distance(eventPosition) < 32
                and nextPosition:Distance(eventPosition) <= player.Position:Distance(eventPosition)
            then return false, "spike_or_tnt" end
        end
    end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local trackingBomb = trackingBombInfo(entity, player)
        if trackingBomb then
            local center = entity.Position + (entity.Velocity or Vector(0, 0)) * 8
            local radius = trackingBomb.radius + 18
            local currentDistance = player.Position:Distance(center)
            local nextDistance = nextPosition:Distance(center)
            local middleDistance = (player.Position + candidate * 14):Distance(center)
            if (nextDistance < radius or middleDistance < radius)
                and nextDistance <= currentDistance then return false, "ghost_bomb" end
        end
        if isMovingSpikeTrap(entity) then
            local radius = math.max(35, math.min(55, (tonumber(entity.Size) or 20) + (tonumber(player.Size) or 10) + 10))
            for _, center in ipairs({ entity.Position, entity.Position + entity.Velocity * 4 }) do
                local currentDistance = player.Position:Distance(center)
                local nextDistance = nextPosition:Distance(center)
                local middleDistance = (player.Position + candidate * 14):Distance(center)
                if (nextDistance < radius or middleDistance < radius)
                    and nextDistance <= currentDistance then return false, "moving_spike" end
            end
        end
        if liveHazardKind(entity) == "fire" or bombOnlyFireKind(liveHazardKind(entity)) then
            local radius = math.max(36, (tonumber(player.Size) or 10) + (tonumber(entity.Size) or 15) + 8)
            local currentDistance = player.Position:Distance(entity.Position)
            local nextDistance = nextPosition:Distance(entity.Position)
            local middleDistance = (player.Position + candidate * 14):Distance(entity.Position)
            if (nextDistance < radius or middleDistance < radius)
                and nextDistance <= currentDistance then return false, "fire" end
        end
        if dangerousCreep(entity) then
            local radius = math.max(24, math.min(65, tonumber(entity.Size) or 28)) + 18
            local currentDistance = player.Position:Distance(entity.Position)
            local nextDistance = nextPosition:Distance(entity.Position)
            local middleDistance = (player.Position + candidate * 14):Distance(entity.Position)
            if (nextDistance < radius or middleDistance < radius)
                and nextDistance <= currentDistance then return false, "creep" end
        end
    end
    for _, offset in ipairs({ Vector(0, 0), Vector(-40, 0), Vector(40, 0),
        Vector(0, -40), Vector(0, 40), Vector(-40, -40), Vector(40, -40),
        Vector(-40, 40), Vector(40, 40) }) do
        local other = room:GetGridEntity(room:GetGridIndex(nextPosition + offset))
        if other and (liveGridHazardKind(other) == "fire" or bombOnlyFireKind(liveGridHazardKind(other)))
            and nextPosition:Distance(other.Position) < 36
            and nextPosition:Distance(other.Position) <= player.Position:Distance(other.Position) then return false, "grid_fire" end
    end
    if bombStillLive() and bombPosition and not plannedBombRetreat
        and nextPosition:Distance(bombPosition) < player.Position:Distance(bombPosition)
        and nextPosition:Distance(bombPosition) < 120 then return false, "bomb_blast" end
    return true, "safe"
end

local function firstSafeMove(player, desired, allowDoorThreshold)
    if desired:Length() < 0.5 then return Vector(0, 0) end
    if allowDoorThreshold then
        return safeMoveCandidate(player, desired, true) and desired or Vector(0, 0)
    end
    local candidates = { desired, Vector(-desired.Y, desired.X), Vector(desired.Y, -desired.X), Vector(-desired.X, -desired.Y) }
    for index, candidate in ipairs(candidates) do
        if safeMoveCandidate(player, candidate, false) then return candidate end
    end
    return Vector(0, 0)
end

local function projectedHazardLaneClear(room, startPosition, targetPosition, direction)
    if room:GetGridPath(room:GetGridIndex(startPosition)) >= 1000 then return false end
    local distance = startPosition:Distance(targetPosition)
    for step = 40, distance - 40, 20 do
        local point = startPosition + direction * step
        if room:GetGridPath(room:GetGridIndex(point)) >= 1000 then return false end
    end
    return true
end

local function hazardLaneCorrection(player, target, targetId)
    local roomKey = currentRoomKey()
    if hazardLaneRoomKey ~= roomKey or hazardLaneTargetId ~= targetId then
        hazardLaneRoomKey, hazardLaneTargetId, hazardLaneAxis = roomKey, targetId, ""
    end
    local delta = target.Position - player.Position
    local maximumRange = math.max(0, player.TearRange - 25)
    local horizontal = math.abs(delta.X) >= 70 and math.abs(delta.X) <= maximumRange
    local vertical = math.abs(delta.Y) >= 70 and math.abs(delta.Y) <= maximumRange
    local room = game:GetRoom()
    local horizontalDirection = Vector(delta.X >= 0 and 1 or -1, 0)
    local verticalDirection = Vector(0, delta.Y >= 0 and 1 or -1)
    local horizontalClear = horizontal and projectedHazardLaneClear(room,
        Vector(player.Position.X, target.Position.Y), target.Position, horizontalDirection)
    local verticalClear = vertical and projectedHazardLaneClear(room,
        Vector(target.Position.X, player.Position.Y), target.Position, verticalDirection)
    if hazardLaneAxis == "horizontal" and (not horizontalClear or math.abs(delta.Y) > 80) then hazardLaneAxis = "" end
    if hazardLaneAxis == "vertical" and (not verticalClear or math.abs(delta.X) > 80) then hazardLaneAxis = "" end
    if hazardLaneAxis == "" then
        if horizontalClear and math.abs(delta.Y) <= 36 then hazardLaneAxis = "horizontal"
        elseif verticalClear and math.abs(delta.X) <= 36 then hazardLaneAxis = "vertical" end
    end
    if hazardLaneAxis == "" then return nil end
    local offset = hazardLaneAxis == "horizontal" and delta.Y or delta.X
    local velocity = hazardLaneAxis == "horizontal" and player.Velocity.Y or player.Velocity.X
    if math.abs(offset) <= 14 and math.abs(velocity) <= 1.3 then return Vector(0, 0) end
    local correction = offset - velocity * 4
    if math.abs(correction) <= 10 then return Vector(0, 0) end
    local move = hazardLaneAxis == "horizontal"
        and Vector(0, correction > 0 and 1 or -1)
        or Vector(correction > 0 and 1 or -1, 0)
    -- Never replace a blocked braking step with a perpendicular detour: that
    -- would move the player out of the firing lane and restart the oscillation.
    return safeMoveCandidate(player, move, false) and move or Vector(0, 0)
end

local function resolveSafeMove(player)
    local desired = action.move
    local room = game:GetRoom()
    local roomIndex = game:GetLevel():GetCurrentRoomIndex()
    if bombStillLive() and bombPosition
        and player.Position:Distance(bombPosition) < 145 then
        -- Keep the preflighted escape direction. Re-deriving it from current
        -- velocity turned a slight drift toward the wall into a fatal U-turn.
        if safeMoveCandidate(player, bombRetreatDirection, false, true) then
            return bombRetreatDirection
        end
        for _, side in ipairs({ Vector(-bombRetreatDirection.Y, bombRetreatDirection.X),
                                Vector(bombRetreatDirection.Y, -bombRetreatDirection.X) }) do
            if (player.Position + side * 28):Distance(bombPosition)
                > player.Position:Distance(bombPosition) + 1
                and safeMoveCandidate(player, side, false, true) then return side end
        end
        return Vector(0, 0)
    end
    local trackingBomb = nearestTrackingBomb(player)
    if trackingBomb then
        local threatPosition = Vector(trackingBomb.pos.x, trackingBomb.pos.y)
        local predicted = threatPosition + Vector(trackingBomb.vel.x, trackingBomb.vel.y) * 8
        local away = player.Position - predicted
        local primary = math.abs(away.X) >= math.abs(away.Y)
            and Vector(away.X >= 0 and 1 or -1, 0)
            or Vector(0, away.Y >= 0 and 1 or -1)
        local candidates = { primary, Vector(-primary.Y, primary.X), Vector(primary.Y, -primary.X), Vector(-primary.X, -primary.Y) }
        for _, candidate in ipairs(candidates) do
            if safeMoveCandidate(player, candidate, false) then return candidate end
        end
        return Vector(0, 0)
    end
    if action.sourceRoomIndex >= 0 and action.sourceRoomIndex ~= roomIndex then return Vector(0, 0) end
    if action.mode == "recovery" and action.waypoint then
        local delta = action.waypoint - player.Position
        if delta:Length() <= 12 then return Vector(0, 0) end
        local primary = math.abs(delta.X) >= math.abs(delta.Y)
            and Vector(delta.X >= 0 and 1 or -1, 0)
            or Vector(0, delta.Y >= 0 and 1 or -1)
        local secondary = math.abs(primary.X) > 0
            and Vector(0, delta.Y >= 0 and 1 or -1)
            or Vector(delta.X >= 0 and 1 or -1, 0)
        if safeMoveCandidate(player, primary, false) then return primary end
        if math.abs(primary.X) > 0 and math.abs(delta.Y) > 12
            and safeMoveCandidate(player, secondary, false) then return secondary end
        if math.abs(primary.Y) > 0 and math.abs(delta.X) > 12
            and safeMoveCandidate(player, secondary, false) then return secondary end
        return Vector(0, 0)
    end
    local buttonId = tonumber(string.match(action.id or "", "^press_button_(%-?%d+)$"))
    if action.mode == "button" and buttonId then
        local buttonIndex = buttonId <= -100000 and (-100000 - buttonId) or buttonId
        local button = room:GetGridEntity(buttonIndex)
        local event = gridEvent(button, buttonIndex)
        if not event or event.kind ~= "button" or event.triggered then return Vector(0, 0) end
        local delta = button.Position - player.Position
        if delta:Length() <= 12 then return Vector(0, 0) end
        if action.move:Length() > 0.5 then return firstSafeMove(player, action.move, false) end
        return firstSafeMove(player, math.abs(delta.X) >= math.abs(delta.Y)
            and Vector(delta.X >= 0 and 1 or -1, 0)
            or Vector(0, delta.Y >= 0 and 1 or -1), false)
    end
    local tntId = tonumber(string.match(action.id or "", "^shoot_tnt_(%-?%d+)$"))
    if action.mode == "tnt" and tntId then
        local tntIndex = tntId <= -100000 and (-100000 - tntId) or tntId
        local tnt = room:GetGridEntity(tntIndex)
        local event = gridEvent(tnt, tntIndex)
        if not event or event.kind ~= "tnt" or not event.active then return Vector(0, 0) end
        local distance = tnt.Position:Distance(player.Position)
        if distance < 135 then
            local away = player.Position - tnt.Position
            return firstSafeMove(player, math.abs(away.X) >= math.abs(away.Y)
                and Vector(away.X >= 0 and 1 or -1, 0)
                or Vector(0, away.Y >= 0 and 1 or -1), false)
        end
        return firstSafeMove(player, action.move, false)
    end
    local bossExitGrid = tonumber(string.match(action.id or "", "^enter_boss_exit_(%-?%d+)$"))
    local bossExitNavigation = action.mode == "boss_exit" and bossExitGrid ~= nil
    if bossExitNavigation then
        local trapdoor = room:GetGridEntity(bossExitGrid)
        local typeOk, trapdoorType = pcall(function() return trapdoor and trapdoor:GetType() or -1 end)
        if not typeOk then trapdoorType = -1 end
        if not trapdoor or trapdoorType ~= GRID_TRAPDOOR_TYPE then return Vector(0, 0) end
        local trapdoorPosition = trapdoor.Position
        local delta = trapdoorPosition - player.Position
        if delta:Length() <= 24 then return Vector(0, 0) end
        if math.abs(delta.X) >= math.abs(delta.Y) then
            desired = Vector(delta.X >= 0 and 1 or -1, 0)
        else
            desired = Vector(0, delta.Y >= 0 and 1 or -1)
        end
        return firstSafeMove(player, desired, false)
    end
    -- Use the engine's door position for navigation. Room grid indices around
    -- doors can be rotated by room shapes, which previously sent the player
    -- away from a right-hand exit.
    local doorSlot = tonumber(string.match(action.id or "", "^enter_door_(%d+)$"))
    local navigationDoor = action.mode == "navigate" and doorSlot ~= nil
    if action.mode == "navigate" and doorSlot then
        -- Use the stable slot side, but first align the perpendicular axis
        -- with the actual door center. Pressing only toward a right/left door
        -- while Isaac is above or below its center traps him against the wall.
        local doorPosition = actualDoorPosition(room, doorSlot)
        local doorSide = doorSlotDirection(doorSlot)
        local delta = doorPosition - player.Position
        -- A remote/grid instruction can arrive several frames after Isaac
        -- reaches the narrow horizontal door lane. Use live coordinates to
        -- start crossing immediately instead of overshooting and oscillating.
        if math.abs(doorSide.X) > 0.5 and math.abs(delta.X) > 70
            and math.abs(delta.Y) <= 42 and safeMoveCandidate(player, doorSide, false) then
            desired = doorSide
        elseif delta:Length() > 90 and action.move:Length() > 0.5 then
            desired = action.move
        elseif math.abs(doorSide.X) > 0.5 and math.abs(delta.Y) > 12 then
            desired = Vector(0, delta.Y >= 0 and 1 or -1)
        elseif math.abs(doorSide.Y) > 0.5 and math.abs(delta.X) > 12 then
            desired = Vector(delta.X >= 0 and 1 or -1, 0)
        else
            desired = doorSide
        end
    end
    if navigationDoor then
        if hasCombatEnemy() then return Vector(0, 0) end
        local doorDistance = player.Position:Distance(actualDoorPosition(room, doorSlot))
        local entering = doorDistance <= 70 and desired.X == doorSlotDirection(doorSlot).X and desired.Y == doorSlotDirection(doorSlot).Y
        -- During door alignment a fallback side-step can push Isaac into the
        -- threshold wall while the requested perpendicular move is ignored.
        -- Let the controller choose a new approach instead of claiming that
        -- the door itself is permanently unreachable.
        if not entering then
            return safeMoveCandidate(player, desired, false) and desired or Vector(0, 0)
        end
        return firstSafeMove(player, desired, true)
    end
    local projectileMove = nil
    local projectileDistance = nil
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PROJECTILE then
            local delta = player.Position - entity.Position
            local distance = delta:Length()
            local velocity = entity.Velocity
            local closing = delta.X * velocity.X + delta.Y * velocity.Y > 0.25
            if distance <= 120 and (closing or distance <= 70) and (not projectileDistance or distance < projectileDistance) then
                projectileDistance = distance
                if math.abs(velocity.X) >= math.abs(velocity.Y) and math.abs(velocity.X) > 0.1 then
                    projectileMove = Vector(0, velocity.X >= 0 and 1 or -1)
                elseif math.abs(velocity.Y) > 0.1 then
                    projectileMove = Vector(velocity.Y >= 0 and -1 or 1, 0)
                else
                    projectileMove = Vector(delta.X >= 0 and 1 or -1, 0)
                end
            end
        end
    end
    if not projectileMove then
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if isCombatEnemy(entity) then
                local velocity = entity.Velocity
                local speed = velocity:Length()
                local toPlayer = player.Position - entity.Position
                local approaching = toPlayer.X * velocity.X + toPlayer.Y * velocity.Y > 0
                local projected = entity.Position + velocity * 10
                if speed >= 3.5 and approaching and toPlayer:Length() < 190
                    and projected:Distance(player.Position) < 80 then
                    local side = Vector(-velocity.Y, velocity.X)
                    if side:Length() > 0 then
                        side = math.abs(side.X) >= math.abs(side.Y)
                            and Vector(side.X >= 0 and 1 or -1, 0)
                            or Vector(0, side.Y >= 0 and 1 or -1)
                        local opposite = Vector(-side.X, -side.Y)
                        local first = player.Position + side * 40
                        local second = player.Position + opposite * 40
                        if first:Distance(projected) < second:Distance(projected) then side = opposite end
                        projectileMove = firstSafeMove(player, side, false)
                    end
                    break
                end
            end
        end
    end
    local pickupId = tonumber(string.match(action.id or "", "^take_[a-z]+_(%-?%d+)$"))
    if not pickupId then pickupId = tonumber(string.match(action.id or "", "^open_chest_(%-?%d+)$")) end
    if (action.mode == "item" or action.mode == "shop" or action.mode == "pickup" or action.mode == "chest") and pickupId then
        local target = nil
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity.Type == EntityType.ENTITY_PICKUP and entity.Index == pickupId then
                target = entity
                break
            end
        end
        if target then
            local delta = target.Position - player.Position
            -- Python's move_towards uses the room grid to route around rocks
            -- and other blockers. Do not overwrite that first path step with
            -- a direct line toward the pickup; doing so makes reachable items
            -- look stuck and causes the controller to abandon them.
            if action.move:Length() > 0.5 then
                desired = action.move
            elseif math.abs(delta.X) > 16 or math.abs(delta.Y) > 16 then
                if math.abs(delta.X) >= math.abs(delta.Y) then
                    desired = Vector(delta.X >= 0 and 1 or -1, 0)
                else
                    desired = Vector(0, delta.Y >= 0 and 1 or -1)
                end
            else
                desired = Vector(0, 0)
            end
        else
            -- The pickup was collected or despawned; wait for the next state
            -- rather than following a stale grid direction into an obstacle.
            desired = Vector(0, 0)
        end
    end
    local hazardId = tonumber(string.match(action.id or "", "^clear_hazard_(%-?%d+)$"))
    local hazardTarget = nil
    if action.mode == "hazard" and hazardId then
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity.Index == hazardId and liveHazardKind(entity) then
                hazardTarget = entity
                break
            end
        end
        if not hazardTarget and hazardId <= -100000 then
            local gridIndex = -100000 - hazardId
            local grid = room:GetGridEntity(gridIndex)
            if liveGridHazardKind(grid) then hazardTarget = grid end
        end
        -- Python may request a small lateral correction to line up a
        -- cardinal tear. It must never become a direct contact move.
        desired = action.move
    end
    local bombId = tonumber(string.match(action.id or "", "^bomb_hazard_(%-?%d+)$"))
    local bombTarget = nil
    if action.mode == "bomb_wall" then
        if not action.bombSite then return Vector(0, 0) end
        local delta = action.bombSite - player.Position
        if delta:Length() <= 14 then return Vector(0, 0) end
        if action.move:Length() > 0.5 then return firstSafeMove(player, action.move, false) end
        return firstSafeMove(player, math.abs(delta.X) >= math.abs(delta.Y)
            and Vector(delta.X >= 0 and 1 or -1, 0)
            or Vector(0, delta.Y >= 0 and 1 or -1), false)
    end
    if action.mode == "bomb" and bombId then
        for index = 0, room:GetGridSize() - 1 do
            if -100000 - index == bombId then
                local grid = room:GetGridEntity(index)
                if liveGridHazardKind(grid) == "xrock" then bombTarget = grid end
                break
            end
        end
        if not bombTarget then return Vector(0, 0) end
        if not action.bombSite then return Vector(0, 0) end
        local delta = action.bombSite - player.Position
        if delta:Length() <= 14 then return Vector(0, 0) end
        if action.move:Length() > 0.5 then return firstSafeMove(player, action.move, false) end
        return firstSafeMove(player, math.abs(delta.X) >= math.abs(delta.Y)
            and Vector(delta.X >= 0 and 1 or -1, 0)
            or Vector(0, delta.Y >= 0 and 1 or -1), false)
    end
    local nearest, distance = nil, nil
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if isCombatEnemy(entity) then
            local currentDistance = entity.Position:Distance(player.Position)
            if not distance or currentDistance < distance then nearest, distance = entity, currentDistance end
        end
    end
    if nearest and distance < 95 then
        local away = player.Position - nearest.Position
        if math.abs(away.X) >= math.abs(away.Y) then desired = Vector(away.X >= 0 and 1 or -1, 0)
        else desired = Vector(0, away.Y >= 0 and 1 or -1) end
    end
    if action.mode ~= "hazard" and projectileMove then desired = projectileMove end
    -- If the previous resolved direction produced no displacement, rotate it
    -- before applying the enemy-avoidance result again. This closes the loop
    -- at the game-input layer instead of repeatedly pushing into one wall.
    if action.mode ~= "hazard" and not projectileMove and lastMovementBlocked and lastResolvedMove:Length() > 0.5 then
        desired = Vector(-lastResolvedMove.Y, lastResolvedMove.X)
    end
    if action.mode == "hazard" then
        if not hazardTarget then
            hazardLaneAxis = ""
            return Vector(0, 0)
        end
        if nearest and distance < 95 then
            hazardLaneAxis = ""
            return firstSafeMove(player, desired, false)
        end
        local correction = hazardLaneCorrection(player, hazardTarget, hazardId)
        if correction then return correction end
    else
        hazardLaneAxis = ""
    end
    -- The Python route already ends at a safe firing lane. Contact checks in
    -- safeMoveCandidate are the sole proximity guard; a second 90px retreat
    -- rule used to reverse the approach step before the lane was reached.
    if desired:Length() < 0.5 then return Vector(0, 0) end
    return firstSafeMove(player, desired, false)
end

local function actionHazardStillPresent()
    if action.mode ~= "hazard" and action.mode ~= "bomb" then return true end
    local hazardId = tonumber(string.match(action.id or "", "^clear_hazard_(%-?%d+)$"))
    if action.mode == "bomb" then
        hazardId = tonumber(string.match(action.id or "", "^bomb_hazard_(%-?%d+)$"))
        local bossId = tonumber(string.match(action.id or "", "^bomb_boss_(%-?%d+)$"))
        if bossId then
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Index == bossId and isCombatEnemy(entity) then return true end
            end
            return false
        end
    end
    if not hazardId then return false end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Index == hazardId then
            local kind = liveHazardKind(entity)
            -- A stale pre-v13 clear action must not make blue fire a tear
            -- target after the Mod is reloaded.
            if bombOnlyFireKind(kind) and action.mode == "hazard" then return false end
            if kind then return true end
        end
    end
    if hazardId <= -100000 then
        local gridIndex = -100000 - hazardId
        local kind = liveGridHazardKind(game:GetRoom():GetGridEntity(gridIndex))
        return kind ~= nil and (kind ~= "xrock" or game:GetPlayer(0):GetNumBombs() > 0 or bombPlaced)
    end
    return false
end

local function actionPickupStillPresent()
    if action.mode ~= "item" and action.mode ~= "shop" and action.mode ~= "pickup" and action.mode ~= "chest" then return true end
    local pickupId = tonumber(string.match(action.id or "", "^take_[a-z]+_(%-?%d+)$"))
    if not pickupId then pickupId = tonumber(string.match(action.id or "", "^open_chest_(%-?%d+)$")) end
    if not pickupId or ignoredPickup(pickupId) then return false end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Index == pickupId then return true end
    end
    return false
end

local function bombEscapeDirection(player, preferred, avoidEnemies)
    local room = game:GetRoom()
    local directions = { Vector(1, 0), Vector(-1, 0), Vector(0, 1), Vector(0, -1) }
    table.sort(directions, function(a, b)
        return a.X * preferred.X + a.Y * preferred.Y > b.X * preferred.X + b.Y * preferred.Y
    end)
    for _, direction in ipairs(directions) do
        if (not avoidEnemies or direction.X * preferred.X + direction.Y * preferred.Y >= 0)
            and safeMoveCandidate(player, direction, false) then
            local corridorClear = true
            for distance = 40, 160, 20 do
                local point = player.Position + direction * distance
                if not room:IsPositionInRoom(point, 12) then corridorClear = false; break end
                local index = room:GetGridIndex(point)
                local grid = room:GetGridEntity(index)
                local event = gridEvent(grid, index)
                if room:GetGridPath(index) >= 1000 or redPoopGrid(grid)
                    or liveGridHazardKind(grid) == "fire"
                    or bombOnlyFireKind(liveGridHazardKind(grid))
                    or (event and event.active and (event.kind == "spike" or event.kind == "tnt")) then
                    corridorClear = false; break
                end
                if avoidEnemies then
                    for _, entity in ipairs(Isaac.GetRoomEntities()) do
                        if (isCombatEnemy(entity) or isMovingSpikeTrap(entity)
                            or dangerousCreep(entity) or liveHazardKind(entity) == "fire"
                            or bombOnlyFireKind(liveHazardKind(entity)))
                            and point:Distance(entity.Position)
                                < (tonumber(entity.Size) or 20) + (tonumber(player.Size) or 10) + 15 then
                            corridorClear = false; break
                        end
                    end
                    if not corridorClear then break end
                end
            end
            if corridorClear then return direction end
        end
    end
    return nil
end

local function tryDropBomb(player)
    if (action.mode ~= "bomb" and action.mode ~= "bomb_wall") or not automatic then return end
    if action.sourceRoomIndex >= 0 and action.sourceRoomIndex ~= game:GetLevel():GetCurrentRoomIndex() then return end
    if action.mode == "bomb_wall" and hasCombatEnemy() then return end
    local bombId = tonumber(string.match(action.id or "", "^bomb_hazard_(%-?%d+)$"))
    local bossId = tonumber(string.match(action.id or "", "^bomb_boss_(%-?%d+)$"))
    local wallSlot = tonumber(string.match(action.id or "", "^bomb_secret_(%d+)$"))
        or tonumber(string.match(action.id or "", "^bomb_super_secret_(%d+)$"))
    if not bombId and not bossId and not wallSlot then return end
    if bombPlaced and bombRoomKey == currentRoomKey() and game:GetFrameCount() - bombPlacedFrame < 120 then return end
    if player:GetNumBombs() <= 0 and not player:HasGoldenBomb() then return end
    local room = game:GetRoom()
    local targetPosition = nil
    if bombId then
        for index = 0, room:GetGridSize() - 1 do
            if -100000 - index == bombId then
                local grid = room:GetGridEntity(index)
                local kind = liveGridHazardKind(grid)
                if kind == "xrock" or bombOnlyFireKind(kind) then
                    if bombOnlyFireKind(kind) and player:GetNumBombs() <= 4 then
                        bombError = "special fire requires more than four bombs"
                        return
                    end
                    targetPosition = grid.Position
                end
                break
            end
        end
        -- Entity hazards use their positive Entity.Index. Blue fire is a
        -- bomb-only entity target; it must never fall through to tear aiming.
        if not targetPosition then
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Index == bombId and bombOnlyFireKind(liveHazardKind(entity)) then
                    if player:GetNumBombs() <= 4 then
                        bombError = "special fire requires more than four bombs"
                        return
                    end
                    targetPosition = entity.Position
                    break
                end
            end
        end
    elseif bossId then
        local descriptor = game:GetLevel():GetCurrentRoomDesc()
        if not descriptor or not descriptor.Data or descriptor.Data.Type ~= RoomType.ROOM_BOSS then return end
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local npc = entity:ToNPC()
            if entity.Index == bossId and isCombatEnemy(entity) and npc then
                local bossOk, isBoss = pcall(function() return npc:IsBoss() end)
                if bossOk and isBoss then
                    targetPosition = entity.Position
                    break
                end
            end
        end
        if not targetPosition then return end
    elseif wallSlot and room:IsDoorSlotAllowed(wallSlot) then
        local door = room:GetDoor(wallSlot)
        if door and door:IsOpen() then return end
        targetPosition = actualDoorPosition(room, wallSlot)
    end
    if not targetPosition then return end
    if not bossId and (not action.bombSite or player.Position:Distance(action.bombSite) > 14) then return end
    local distance = targetPosition:Distance(player.Position)
    if bombId and (distance < 24 or distance > 70) then return end
    if bossId and (distance < 55 or distance > 110) then return end
    if wallSlot and (distance < 32 or distance > 90) then return end
    local preferred = wallSlot and (room:GetCenterPos() - player.Position) or (player.Position - targetPosition)
    local escape = bombEscapeDirection(player, preferred, bossId ~= nil)
    if not escape then bombError = "no clear bomb escape corridor"; return end
    local ok, spawnedBomb = pcall(function()
        -- Blast reach and escape are separate checks: the player immediately
        -- leaves the bomb after placement, even if the next policy action changes.
        return player:FireBomb(player.Position, Vector(0, 0), player)
    end)
    if ok and spawnedBomb then
        bombTargetId = bombId or bossId or (-200000 - wallSlot)
        bombPlaced = true
        bombPlacedFrame = game:GetFrameCount()
        bombPosition = Vector(spawnedBomb.Position.X, spawnedBomb.Position.Y)
        bombEntity = spawnedBomb
        bombPlacementDistance = distance
        bombRetreatDirection = escape
        player.Velocity = Vector(0, 0)
        resolvedMove = escape
        bombRoomKey = currentRoomKey()
        if wallSlot then bombedWallKeys[currentRoomKey() .. ":" .. tostring(wallSlot)] = true end
        -- A resource bookkeeping failure must never suppress the retreat
        -- after a bomb has already appeared in the room.
        local consumed, consumeError = pcall(function()
            if not player:HasGoldenBomb() then player:AddBombs(-1) end
        end)
        bombError = consumed and nil or tostring(consumeError)
    else
        bombError = ok and "FireBomb returned no bomb" or tostring(spawnedBomb)
    end
end

local function tryEnterSelectedDoor(player)
    transitionGate = "checking"
    transitionDoorDistance = -1
    if action.mode == "boss_exit" then
        if hasCombatEnemy() then transitionGate = "combat_present"; return true end
        transitionGate = "boss_exit_navigation"
        transitionPhase = "native_trapdoor_only"
        return false
    end
    if action.mode ~= "navigate" then transitionGate = "not_navigation"; return false end
    if hasCombatEnemy() then transitionGate = "combat_present"; return false end
    if game:GetFrameCount() - lastActionFrame > 45 then
        transitionPhase = "waiting_for_fresh_action"
        transitionGate = "stale_action"
        return true
    end
    local doorSlot = tonumber(string.match(action.id or "", "^enter_door_(%d+)$"))
    if not doorSlot then
        -- The Python stall breaker keeps the previous mode for diagnostics,
        -- but its lateral reposition is not a door command. Let the generic
        -- collision-safe resolver execute that escape move.
        transitionGate = "navigation_override"
        return false
    end
    local level, room = game:GetLevel(), game:GetRoom()
    local roomIndex = level:GetCurrentRoomIndex()
    if action.sourceRoomIndex >= 0 and action.sourceRoomIndex ~= roomIndex then transitionGate = "source_room_mismatch"; return true end
    if doorAttemptRoomIndex ~= roomIndex or doorAttemptSlot ~= doorSlot then
        doorAttemptRoomIndex = roomIndex
        doorAttemptSlot = doorSlot
        transitionPhase = "native_door_only"
        transitionError = nil
    end
    local door = room:GetDoor(doorSlot)
    if not door then transitionGate = "door_missing"; return true end
    if not door.TargetRoomIndex or door.TargetRoomIndex < 0 then transitionGate = "door_target_missing"; return true end
    local targetDesc = level:GetRoomByIdx(door.TargetRoomIndex, currentDimension(level))
    local targetType = targetDesc and targetDesc.Data and targetDesc.Data.Type or nil
    local hiddenTarget = targetType == RoomType.ROOM_SECRET or targetType == RoomType.ROOM_SUPERSECRET
    local openOk, open = pcall(function() return door:IsOpen() end)
    local lockOk, locked = pcall(function() return door:IsLocked() end)
    local keyDoor = targetType == RoomType.ROOM_TREASURE or targetType == RoomType.ROOM_SHOP
        or targetType == RoomType.ROOM_LIBRARY
    local canUnlock = lockOk and locked == true and keyDoor and player:GetNumKeys() > 0
    if openOk and type(open) == "boolean" and not open and not canUnlock then
        transitionGate = "door_closed"
        return true
    end
    if hiddenTarget then
        if locked or ((not lockOk or type(locked) ~= "boolean") and not (openOk and open)) then
            transitionPhase = "hidden_door_blocked"
            transitionGate = "hidden_door_locked"
            transitionError = "hidden room is locked or lock state is unknown"
            return true
        end
    end
    if action.targetRoomIndex >= 0 and door.TargetRoomIndex ~= action.targetRoomIndex then
        transitionError = "door target mismatch: planned " .. tostring(action.targetRoomIndex) .. " actual " .. tostring(door.TargetRoomIndex)
        transitionPhase = "target_mismatch"
        transitionGate = "target_mismatch"
        return true
    end
    -- A late JEV response can arrive after a successful transition and ask
    -- for the door we just used in reverse. When another real door exists,
    -- hold the old command briefly so Python can publish the new floor-plan
    -- decision instead of bouncing between two rooms through the API.
    if roomIndex == lastTransitionTargetRoomIndex
        and door.TargetRoomIndex == lastTransitionSourceRoomIndex
        and game:GetFrameCount() - roomEntryFrame < backtrackGuardFrames
    then
        local alternative = false
        for slot = 0, 7 do
            local candidate = room:GetDoor(slot)
            if candidate and candidate.TargetRoomIndex and candidate.TargetRoomIndex >= 0
                and candidate.TargetRoomIndex ~= lastTransitionSourceRoomIndex
            then
                local openOk, open = pcall(function() return candidate:IsOpen() end)
                if openOk and open == true then
                    alternative = true
                    break
                end
            end
        end
        if alternative then
            transitionError = "reverse door blocked after entry: " .. tostring(door.TargetRoomIndex)
            transitionPhase = "backtrack_blocked"
            transitionGate = "reverse_guard"
            return false
        end
    end
    local actualPosition = actualDoorPosition(room, doorSlot)
    local fallbackPosition = room:GetDoorSlotPosition(doorSlot)
    local actualDistance = player.Position:Distance(actualPosition)
    local fallbackDistance = player.Position:Distance(fallbackPosition)
    local distance = math.min(actualDistance, fallbackDistance)
    transitionDoorDistance = distance
    if distance > 120 then
        transitionPhase = "native_door_only"
        transitionGate = "too_far"
        return false
    end
    -- Room changes must come from Isaac's ordinary door input. Never call a
    -- room-transition API here: a stale or mismatched action could otherwise
    -- send Isaac through the wrong door and leave him inside a wall.
    transitionPhase = "native_door_only"
    transitionGate = lastMovementBlocked and "native_input_blocked" or "native_input"
    return false
end

local function syncRoomTransitionState()
    local roomIndex = game:GetLevel():GetCurrentRoomIndex()
    if roomIndex ~= lastObservedRoomIndex then
        local previousRoomIndex = lastObservedRoomIndex
        lastObservedRoomIndex = roomIndex
        roomEntryFrame = game:GetFrameCount()
        roomEnteredFrame = roomEntryFrame
        roomVisitSequence = roomVisitSequence + 1
        roomClearedFrame = -1
        lastEnemyCount = 0
        if previousRoomIndex >= 0 and previousRoomIndex ~= roomIndex then
            lastTransitionSourceRoomIndex = previousRoomIndex
            lastTransitionTargetRoomIndex = roomIndex
        end
        transitionPhase = "entered"
        transitionError = nil
        doorAttemptRoomIndex = -1
        doorAttemptSlot = -1
        bombTargetId, bombPlaced, bombPosition, bombRoomKey = -1, false, nil, ""
        bombEntity = nil
        bombPlacementDistance = -1
        bombPlacedFrame = -1
        bombRetreatActive = false
        nativeSeenTears = {}
        nativeTearFrame, nativeFireStartFrame = -10000, -1
        lastTrinketSwapTarget = -1
        trinketSwapResult = "idle"
        action = { id = "", move = Vector(0, 0), shoot = Vector(0, 0), mode = "combat", target = "", reason = "", sourceRoomIndex = -1 }
    end
end

local function ensureClient()
    if not socketOk or not Json then return false end
    if client then return true end
    local created, createErr = socket.tcp()
    if not created then
        Isaac.DebugString("[IsaacJev] socket create failed: " .. tostring(createErr))
        return false
    end
    created:settimeout(0)
    local connected, connectErr = created:connect(HOST, PORT)
    if not connected and connectErr ~= "timeout" and connectErr ~= "Operation already in progress" then
        created:close()
        bridgeStatus = "connect error: " .. tostring(connectErr)
        return false
    end
    client = created
    bridgeStatus = connected and "connected" or "connecting"
    return true
end

local function closeClient()
    if client then client:close() end
    client = nil
    pendingState = nil
    bridgeStatus = "disconnected"
end

local function readActions()
    if not client or not Json then return end
    while true do
        local line, err = client:receive("*l")
        if not line then
            if err == "closed" then closeClient() end
            return
        end
        local ok, message = pcall(Json.decode, line)
        if ok and type(message) == "table" and message.type == "action" then
            bridgeStatus = "connected"
            automatic = message.enabled == true and not manualOverride
            local previousActionId = action.id
            local previousActionSequence = currentActionSequence
            local move = message.move or {}
            local shoot = message.shoot or {}
            action.id = message.id or ""
            action.move = Vector(tonumber(move.x) or 0, tonumber(move.y) or 0)
            action.shoot = Vector(tonumber(shoot.x) or 0, tonumber(shoot.y) or 0)
            local bombSite = message.bomb_site
            action.bombSite = type(bombSite) == "table"
                and Vector(tonumber(bombSite.x) or 0, tonumber(bombSite.y) or 0) or nil
            local waypoint = message.waypoint
            action.waypoint = type(waypoint) == "table"
                and Vector(tonumber(waypoint.x) or 0, tonumber(waypoint.y) or 0) or nil
            action.mode = message.mode or "combat"
            action.target = message.target or ""
            action.reason = message.reason or ""
            action.sourceRoomIndex = tonumber(message.source_room_index) or -1
            action.targetRoomIndex = tonumber(message.target_room_index) or -1
            action.ignoredHazardIds = message.ignored_hazard_ids or {}
            action.ignoredPickupIds = message.ignored_pickup_ids or {}
            currentActionSequence = tonumber(message.action_sequence) or 0
            -- Keep placement state across model waits and action revisions.
            -- The room transition or a new run clears it instead.
            if transitionPhase == "backtrack_blocked"
                and (action.id ~= previousActionId or currentActionSequence ~= previousActionSequence)
            then
                -- A new planner response supersedes the old blocked reverse
                -- door. Do not carry the stale zero-movement state forever.
                transitionPhase = "entered"
                transitionError = nil
            end
            lastActionFrame = game:GetFrameCount()
        end
    end
end

local function flushPendingState()
    if not client or not pendingState then return end
    local sent, err, partial = client:send(pendingState)
    if sent then
        pendingState = nil
        sentStateCount = sentStateCount + 1
        bridgeStatus = "connected tx=" .. tostring(sentStateCount)
        return
    end
    if partial and partial > 0 then
        pendingState = string.sub(pendingState, partial + 1)
    end
    if err ~= "timeout" then
        bridgeStatus = "send error: " .. tostring(err)
        closeClient()
    end
end

local function sendState()
    if not ensureClient() then return end
    readActions() -- Drain old responses before emitting the next observation.
    flushPendingState()
    -- A full JSON state can be larger than one nonblocking TCP write. Do not
    -- generate another observation until the current line (including newline)
    -- has been completely delivered, otherwise Python will wait forever for it.
    if not pendingState and game:GetFrameCount() - lastStateFrame >= 3 then
        local state = collectState()
        local player = Isaac.GetPlayer(0)
        if player then
            local checks = {}
            for _, option in ipairs({ { "up", Vector(0, -1) }, { "down", Vector(0, 1) },
                { "left", Vector(-1, 0) }, { "right", Vector(1, 0) } }) do
                local _, reason = safeMoveCandidate(player, option[2], false)
                checks[option[1]] = reason
            end
            state.safe_move_directions = checks
        end
        pendingState = Json.encode(state) .. "\n"
        lastStateFrame = game:GetFrameCount()
        flushPendingState()
    end
end

local function wants(vector, button)
    if button == ButtonAction.ACTION_LEFT then return vector.X < -0.5 end
    if button == ButtonAction.ACTION_RIGHT then return vector.X > 0.5 end
    if button == ButtonAction.ACTION_UP then return vector.Y < -0.5 end
    if button == ButtonAction.ACTION_DOWN then return vector.Y > 0.5 end
    if button == ButtonAction.ACTION_SHOOTLEFT then return vector.X < -0.5 end
    if button == ButtonAction.ACTION_SHOOTRIGHT then return vector.X > 0.5 end
    if button == ButtonAction.ACTION_SHOOTUP then return vector.Y < -0.5 end
    if button == ButtonAction.ACTION_SHOOTDOWN then return vector.Y > 0.5 end
    return false
end

local function isShootButton(button)
    return button == ButtonAction.ACTION_SHOOTLEFT
        or button == ButtonAction.ACTION_SHOOTRIGHT
        or button == ButtonAction.ACTION_SHOOTUP
        or button == ButtonAction.ACTION_SHOOTDOWN
end

local function clearTearLane(player, targetPosition, minimumDistance)
    local delta = targetPosition - player.Position
    local distance = delta:Length()
    if distance < minimumDistance or distance > math.max(0, player.TearRange - 15) then
        return Vector(0, 0)
    end
    local direction = Vector(0, 0)
    if math.abs(delta.Y) <= 18 then direction = Vector(delta.X >= 0 and 1 or -1, 0)
    elseif math.abs(delta.X) <= 18 then direction = Vector(0, delta.Y >= 0 and 1 or -1) end
    if direction:Length() < 0.5 then return direction end
    local room = game:GetRoom()
    for step = 40, distance - 40, 20 do
        local point = player.Position + direction * step
        if room:GetGridPath(room:GetGridIndex(point)) >= 1000 then return Vector(0, 0) end
    end
    return direction
end

function mod:onUpdate()
    if Input.IsButtonTriggered(Keyboard.KEY_F8, 0) then
        manualOverride = not manualOverride
        automatic = false
        Isaac.DebugString("[IsaacJev] manual override=" .. (manualOverride and "ON" or "OFF"))
    end
    syncRoomTransitionState()
    local player = Isaac.GetPlayer(0)
    local dead = handleDeathAndRestart(player)
    if lastPlayerPosition then
        lastMovementProgress = player.Position:Distance(lastPlayerPosition)
        lastMovementBlocked = lastResolvedMove:Length() > 0.5 and lastMovementProgress < 0.5
    else
        lastMovementProgress = 0
        lastMovementBlocked = false
    end
    lastPlayerPosition = Vector(player.Position.X, player.Position.Y)
    sendState()
    if dead then
        -- The bridge may reply with an enabled action while the death screen
        -- is visible; never pass that stale action into the input callbacks.
        automatic = false
        resolvedMove = Vector(0, 0)
        return
    end
    if automatic then
        for slot = 0, 3 do
            local color = player:GetPill(slot)
            if not color or color == 0 then
                lastUsedPill[slot] = nil
            elseif lastUsedPill[slot] ~= color then
                lastUsedPill[slot] = color
                local ok, err = pcall(function()
                    local effect = game:GetItemPool():GetPillEffect(color, player)
                    player:UsePill(effect, color)
                    player:SetPill(slot, 0)
                end)
                if ok and player:GetPill(slot) == 0 then lastUsedPill[slot] = nil end
                pillUseResult = ok and ("used:" .. tostring(color)) or ("error:" .. tostring(err))
            end
        end
    end
    local wantedTrinketId = tonumber(string.match(action.id or "", "^take_pickup_(%d+)$"))
    if automatic and wantedTrinketId and wantedTrinketId ~= lastTrinketSwapTarget then
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity.Type == EntityType.ENTITY_PICKUP and entity.Index == wantedTrinketId
                and entity.Variant == PickupVariant.PICKUP_TRINKET
                and entity.Position:Distance(player.Position) < 60 then
                local capacity = math.max(1, player:GetMaxTrinkets())
                local occupied = 0
                for slot = 0, capacity - 1 do
                    if player:GetTrinket(slot) ~= 0 then occupied = occupied + 1 end
                end
                if occupied >= capacity then
                    lastTrinketSwapTarget = wantedTrinketId
                    local delta = entity.Position - player.Position
                    local offset = math.abs(delta.X) >= math.abs(delta.Y)
                        and Vector(delta.X >= 0 and -80 or 80, 0)
                        or Vector(0, delta.Y >= 0 and -80 or 80)
                    local ok, err = pcall(function() player:DropTrinket(player.Position + offset, true) end)
                    trinketSwapResult = ok and ("dropped_for:" .. tostring(wantedTrinketId)) or ("error:" .. tostring(err))
                end
                break
            end
        end
    end
    -- A response can arrive one state packet after the tear destroyed its
    -- target. Do not reuse the old aim vector for even one extra frame.
    if automatic and (action.mode == "hazard" or action.mode == "bomb") and not actionHazardStillPresent() then
        action = { id = "hazard_target_gone", move = Vector(0, 0), shoot = Vector(0, 0), mode = "wait", target = "", reason = "hazard disappeared; waiting for fresh state", sourceRoomIndex = -1 }
        lastActionFrame = -10000
    end
    if automatic and not actionPickupStillPresent() then
        action = { id = "pickup_target_gone", move = Vector(0, 0), shoot = Vector(0, 0), mode = "wait", target = "", reason = "pickup marked unreachable or disappeared; waiting for fresh state", sourceRoomIndex = -1 }
        lastActionFrame = -10000
    end
    local bombNeedsRetreat = bombStillLive() and bombPosition
        and player.Position:Distance(bombPosition) < 145
    bombRetreatActive = bombNeedsRetreat and automatic
    local trackingBombNearby = automatic and nearestTrackingBomb(player) ~= nil
    ghostBombRetreatActive = trackingBombNearby
    local doorInputBlocked = automatic and not bombNeedsRetreat and not trackingBombNearby and tryEnterSelectedDoor(player)
    local blockedReverseDoor = automatic
        and not bombNeedsRetreat and not trackingBombNearby
        and action.mode == "navigate"
        and transitionPhase == "backtrack_blocked"
        and game:GetFrameCount() - roomEntryFrame < backtrackGuardFrames
    resolvedMove = automatic and not doorInputBlocked and not blockedReverseDoor and resolveSafeMove(player) or Vector(0, 0)
    local surpriseEnemy = automatic and not bombNeedsRetreat and not trackingBombNearby and hasCombatEnemy()
        and action.mode ~= "combat" and action.mode ~= "hazard"
        and action.mode ~= "bomb" and action.mode ~= "tnt"
        and action.mode ~= "wait" and action.mode ~= "evade"
    if surpriseEnemy then resolvedMove = Vector(0, 0) end
    if not trackingBombNearby then tryDropBomb(player) end
    lastRequestedMove = Vector(action.move.X, action.move.Y)
    lastResolvedMove = Vector(resolvedMove.X, resolvedMove.Y)
    if not automatic then
        lastMoveResolutionReason = "manual"
    elseif trackingBombNearby then
        lastMoveResolutionReason = "ghost_bomb_retreat"
    elseif doorInputBlocked then
        lastMoveResolutionReason = "door_input_guard"
    elseif blockedReverseDoor then
        lastMoveResolutionReason = "reverse_door_guard"
    elseif action.mode == "hazard" and hazardLaneAxis ~= "" then
        lastMoveResolutionReason = "hazard_lane_control"
    elseif action.mode == "recovery" and action.waypoint
        and player.Position:Distance(action.waypoint) <= 12 then
        lastMoveResolutionReason = "recovery_waypoint_reached"
    elseif lastResolvedMove:Length() < 0.5 and lastRequestedMove:Length() > 0.5 then
        lastMoveResolutionReason = "no_walkable_direction"
    elseif math.abs(lastRequestedMove.X - lastResolvedMove.X) > 0.1 or math.abs(lastRequestedMove.Y - lastResolvedMove.Y) > 0.1 then
        lastMoveResolutionReason = "lua_safety_rewrite"
    else
        lastMoveResolutionReason = "requested"
    end
    fireDirection = action.shoot
    fireBlockReason = "idle"
    if surpriseEnemy or action.mode == "combat" then
        if action.mode == "combat" and not surpriseEnemy and action.shoot:Length() <= 0.5 then
            -- Movement-only combat recovery deliberately holds fire. Do not
            -- replace it with the old local aim fallback.
            fireDirection = Vector(0, 0)
            fireBlockReason = "movement_only_action"
        else
            local liveAim = localFireDirection(player)
            fireDirection = liveAim
            if liveAim:Length() <= 0.5 then fireBlockReason = "no_combat_target" end
        end
    elseif action.mode == "hazard" then
        local hazardId = tonumber(string.match(action.id or "", "^clear_hazard_(%-?%d+)$"))
        local target = nil
        if hazardId then
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Index == hazardId and liveHazardKind(entity) then
                    target = entity
                    break
                end
            end
            if not target and hazardId <= -100000 then
                local grid = game:GetRoom():GetGridEntity(-100000 - hazardId)
                if liveGridHazardKind(grid) then
                    target = grid
                end
            end
        end
        -- The model/controller chooses the hazard target. At game-frame rate,
        -- shoot as soon as the *current* position has a clear cardinal lane;
        -- waiting for the next 3-frame Python decision misses that short window.
        if target and bombOnlyFireKind(liveHazardKind(target)) then
            fireDirection = Vector(0, 0)
            fireBlockReason = "special_fire_bomb_only"
        else
            fireDirection = target and clearTearLane(player, target.Position, 65) or Vector(0, 0)
        end
        if not target then fireBlockReason = "target_missing"
        elseif target and bombOnlyFireKind(liveHazardKind(target)) then fireBlockReason = "special_fire_bomb_only"
        elseif fireDirection:Length() <= 0.5 then
            fireBlockReason = action.shoot:Length() > 0.5 and "range_or_wall" or "approaching_lane"
        end
    elseif action.mode == "tnt" then
        local tntId = tonumber(string.match(action.id or "", "^shoot_tnt_(%-?%d+)$"))
        local tntIndex = tntId and (tntId <= -100000 and (-100000 - tntId) or tntId) or -1
        local tnt = tntIndex >= 0 and game:GetRoom():GetGridEntity(tntIndex) or nil
        local event = gridEvent(tnt, tntIndex)
        fireDirection = Vector(0, 0)
        if event and event.kind == "tnt" and event.active then
            if action.shoot:Length() > 0.5 then
                fireDirection = clearTearLane(player, tnt.Position, 145)
            end
        end
        if not event or not event.active then fireBlockReason = "target_missing"
        elseif action.shoot:Length() <= 0.5 then fireBlockReason = "approaching_lane"
        elseif fireDirection:Length() <= 0.5 then fireBlockReason = "range_or_wall" end
    else
        fireDirection = Vector(0, 0)
    end
    if automatic and nearestTrackingBomb(player) then
        fireDirection = Vector(0, 0)
        fireBlockReason = "ghost_bomb_retreat"
    end
    if fireDirection:Length() > 0.5 then
        if nativeFireStartFrame < 0 then nativeFireStartFrame = game:GetFrameCount() end
    else
        nativeFireStartFrame = -1
    end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_TEAR then
            local ok, owner = pcall(function() return entity.SpawnerEntity end)
            local tearIdentity = entity.InitSeed or entity.Index
            if ok and owner and owner.Index == player.Index and not nativeSeenTears[tearIdentity] then
                nativeSeenTears[tearIdentity] = true
                nativeTearFrame = game:GetFrameCount()
            end
        end
    end
    local currentWeapon = weaponKind(player)
    local needsTearFallback = currentWeapon == "tear" and nativeFireStartFrame >= 0
        and game:GetFrameCount() - nativeFireStartFrame >= 20
        and game:GetFrameCount() - nativeTearFrame >= 20
    if automatic and game:GetFrameCount() - lastActionFrame <= 45 and needsTearFallback
        and fireDirection:Length() > 0.5 and player.FireDelay <= 0 then
        local velocity = fireDirection * math.max(1, player.ShotSpeed * 10)
        local ok, err = pcall(function()
            local tear = player:FireTear(player.Position + player.TearsOffset, velocity, false, false, false)
            if tear then nativeSeenTears[tear.InitSeed or tear.Index] = true end
            player.FireDelay = player.MaxFireDelay
        end)
        if ok then
            firedTearCount = firedTearCount + 1
            fireError = nil
        else
            fireError = tostring(err)
        end
    end
end

function mod:onInput(entity, inputHook, button)
    if not automatic or (game:GetFrameCount() - lastActionFrame > 45
        and not bombRetreatActive and not ghostBombRetreatActive) then return nil end
    if not entity or not entity:ToPlayer() then return nil end
    if isShootButton(button) and (bombRetreatActive or ghostBombRetreatActive
        or game:GetFrameCount() - lastActionFrame > 45) then return nil end
    local vector = isShootButton(button) and fireDirection or resolvedMove
    local pressed = wants(vector, button)
    if inputHook == InputHook.GET_ACTION_VALUE then return pressed and 1.0 or 0.0 end
    return pressed
end

function mod:onEntityTakeDamage(entity, amount, flags, source, countdown)
    appendDamageEvent(entity, amount, flags, source)
end

function mod:onRender()
    local label = "JEV WAITING (bridge)"
    if manualOverride then
        label = "JEV MANUAL (F8: auto)"
    elseif automatic then
        label = "JEV AUTO (F8: manual)"
    end
    Isaac.RenderText(label, 18, 14, automatic and 0.2 or 1, automatic and 1 or 0.8, 0.2, 1)
    Isaac.RenderText(action.mode .. ": " .. action.target, 18, 27, 0.8, 0.9, 1, 1)
    Isaac.RenderText("bridge: " .. bridgeStatus, 18, 40, 0.7, 0.7, 0.7, 1)
    Isaac.RenderText("tears: " .. tostring(firedTearCount), 18, 53, 0.7, 0.7, 0.7, 1)
    if transitionError then Isaac.RenderText("door error: " .. transitionError, 18, 66, 1, 0.4, 0.4, 1) end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, mod.onInput)
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.onEntityTakeDamage)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
