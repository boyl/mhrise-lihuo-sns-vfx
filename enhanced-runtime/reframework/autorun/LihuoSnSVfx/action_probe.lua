local M = {}

local OUTPUT_PATH = "LihuoSnSVfx-action-probe.json"
local MAX_EVENTS = 512
local SAMPLE_INTERVAL_FRAMES = 2
local EXPECTED_GAME_NAME = "MHRise"
local SWORD_AND_SHIELD_WEAPON_TYPE = 8

local state = {
    frame = 0,
    sequence = 0,
    last_key = nil,
    dirty = false,
    status = "initializing",
    events = {},
}

local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function primitive(value)
    if value == nil then return nil end
    if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then return value end
    return safe(function() return value.value__ end)
end

local function read_exact_field(type_definition, instance, name)
    local field = type_definition and safe(function() return type_definition:get_field(name) end) or nil
    if field == nil then return nil end
    return safe(function() return field:get_data(instance) end)
end

local function capture()
    local game_name = safe(function() return reframework:get_game_name() end)
    if game_name ~= EXPECTED_GAME_NAME then
        state.status = "unsupported game: " .. tostring(game_name)
        return
    end

    local manager = safe(function() return sdk.get_managed_singleton("snow.player.PlayerManager") end)
    if manager == nil then state.status = "waiting for PlayerManager" return end
    local manager_type = safe(function() return manager:get_type_definition() end)
    local find_player = manager_type and safe(function() return manager_type:get_method("findMasterPlayer") end) or nil
    if find_player == nil then state.status = "findMasterPlayer unavailable" return end
    local player = safe(function() return find_player:call(manager) end)
    if player == nil then state.status = "waiting for master player" return end

    local player_type = safe(function() return player:get_type_definition() end)
    if player_type == nil then state.status = "player type unavailable" return end
    local weapon_type = tonumber(primitive(read_exact_field(player_type, player, "_playerWeaponType")))
    if weapon_type ~= SWORD_AND_SHIELD_WEAPON_TYPE then
        state.status = "waiting for Sword & Shield; weapon=" .. tostring(weapon_type)
        state.last_key = nil
        return
    end

    local motion_getter = safe(function() return player_type:get_method("getMotionFsm2") end)
    if motion_getter == nil then state.status = "getMotionFsm2 unavailable" return end
    local motion_fsm = safe(function() return motion_getter:call(player) end)
    local motion_type = motion_fsm and safe(function() return motion_fsm:get_type_definition() end) or nil
    local node_method = motion_type and safe(function()
        return motion_type:get_method("getCurrentNodeID(System.Int32)") or motion_type:get_method("getCurrentNodeID")
    end) or nil
    local node_id = node_method and tonumber(primitive(safe(function() return node_method:call(motion_fsm, 0) end))) or nil
    if node_id == nil then state.status = "motion node unavailable" return end

    local node_name = nil
    local layer = safe(function() return motion_fsm:call("getLayer", 0) end)
    local tree = layer and safe(function() return layer:get_tree_object() end) or nil
    local count = tonumber(tree and safe(function() return tree:get_node_count() end) or nil)
    if count and count >= 0 and count <= 4096 then
        local node = safe(function() return tree:get_node(node_id) end)
        node_name = node and safe(function() return node:get_name() end) or nil
    end

    local key = tostring(node_id) .. ":" .. tostring(node_name)
    if key == state.last_key then
        state.status = "observing Sword & Shield"
        return
    end
    state.last_key = key
    state.sequence = state.sequence + 1
    state.events[#state.events + 1] = {
        sequence = state.sequence,
        frame = state.frame,
        weapon_type = weapon_type,
        node_id = node_id,
        node_name = node_name,
    }
    if #state.events > MAX_EVENTS then table.remove(state.events, 1) end
    state.dirty = true
    state.status = "recorded action transition"
end

local function persist()
    if not state.dirty then return end
    local written = safe(function()
        json.dump_file(OUTPUT_PATH, {
            schema_version = 1,
            policy = "read_only_sword_and_shield_action_transitions",
            status = state.status,
            event_count = #state.events,
            events = state.events,
        })
        return true
    end)
    if written then state.dirty = false end
end

re.on_frame(function()
    state.frame = state.frame + 1
    if state.frame % SAMPLE_INTERVAL_FRAMES ~= 0 then return end
    capture()
    persist()
end)

return M
