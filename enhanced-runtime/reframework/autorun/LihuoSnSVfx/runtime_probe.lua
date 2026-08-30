local M = {}

local OUTPUT_PATH = "LihuoSnSVfx-runtime-probe.json"
local EXPECTED_GAME_NAME = "mhrise"
local SWORD_AND_SHIELD_WEAPON_TYPE = 8
local SWORD_AND_SHIELD_PLAYER_TYPE = "snow.player.ShortSword"
local SAMPLE_INTERVAL_FRAMES = 2
local HEARTBEAT_INTERVAL_FRAMES = 120
local MAX_EVENTS = 512

local effect_component_types = {
    "via.effect.script.ObjectEffectManager",
    "via.effect.script.ObjectEffectManager2",
}

local state = {
    frame = 0,
    sequence = 0,
    last_key = nil,
    status = "loaded; waiting for player",
    weapon_type = nil,
    player_type = nil,
    game_object_type = nil,
    effect_components = {},
    events = {},
    dirty = true,
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

local function type_name(value)
    if value == nil then return nil end
    local definition = safe(function() return value:get_type_definition() end)
    return safe(function() return definition:get_full_name() end)
        or safe(function() return definition:get_name() end)
end

local function read_exact_field(type_definition, instance, name)
    local field = type_definition and safe(function() return type_definition:get_field(name) end) or nil
    if field == nil then return nil end
    return safe(function() return field:get_data(instance) end)
end

local function find_player()
    local manager = safe(function() return sdk.get_managed_singleton("snow.player.PlayerManager") end)
    local manager_type = manager and safe(function() return manager:get_type_definition() end) or nil
    local method = manager_type and safe(function() return manager_type:get_method("findMasterPlayer") end) or nil
    return method and safe(function() return method:call(manager) end) or nil
end

local function get_game_object(player)
    return safe(function() return player:call("get_GameObject") end)
        or safe(function() return player:call("getGameObject") end)
end

local function inspect_effect_components(game_object)
    local components = {}
    if game_object == nil then return components end
    for _, requested_type in ipairs(effect_component_types) do
        local runtime_type = safe(function() return sdk.typeof(requested_type) end)
        local component = runtime_type and safe(function()
            return game_object:call("getComponent(System.Type)", runtime_type)
        end) or nil
        components[#components + 1] = {
            requested_type = requested_type,
            available = component ~= nil,
            actual_type = type_name(component),
        }
    end
    return components
end

local function read_motion(player, player_type)
    local getter = safe(function() return player_type:get_method("getMotionFsm2") end)
    local motion_fsm = getter and safe(function() return getter:call(player) end) or nil
    local motion_type = motion_fsm and safe(function() return motion_fsm:get_type_definition() end) or nil
    local node_method = motion_type and safe(function()
        return motion_type:get_method("getCurrentNodeID(System.Int32)")
            or motion_type:get_method("getCurrentNodeID")
    end) or nil
    local node_id = node_method and tonumber(primitive(safe(function()
        return node_method:call(motion_fsm, 0)
    end))) or nil
    if node_id == nil then return nil, nil end

    local node_name = nil
    local layer = safe(function() return motion_fsm:call("getLayer", 0) end)
    local tree = layer and safe(function() return layer:get_tree_object() end) or nil
    local count = tonumber(tree and safe(function() return tree:get_node_count() end) or nil)
    if count and count >= 0 and count <= 4096 then
        local node = safe(function() return tree:get_node(node_id) end)
        node_name = node and safe(function() return node:get_name() end) or nil
    end
    return node_id, node_name
end

local function persist()
    if not state.dirty then return end
    local payload = {
        schema_version = 1,
        policy = "read_only_runtime_discovery_no_effect_calls",
        frame = state.frame,
        status = state.status,
        weapon_type = state.weapon_type,
        player_type = state.player_type,
        game_object_type = state.game_object_type,
        effect_components = state.effect_components,
        event_count = #state.events,
        events = state.events,
    }
    local written = safe(function()
        json.dump_file(OUTPUT_PATH, payload)
        return true
    end)
    if written then state.dirty = false end
end

local function capture()
    local game_name = safe(function() return reframework:get_game_name() end)
    game_name = game_name and string.lower(tostring(game_name)) or nil
    if game_name ~= EXPECTED_GAME_NAME then
        state.status = "unsupported game: " .. tostring(game_name)
        state.dirty = true
        return
    end

    local player = find_player()
    if player == nil then
        state.status = "loaded; waiting for master player"
        state.weapon_type = nil
        state.last_key = nil
        return
    end

    local player_type = safe(function() return player:get_type_definition() end)
    state.player_type = player_type and safe(function() return player_type:get_full_name() end) or nil
    state.weapon_type = tonumber(primitive(read_exact_field(player_type, player, "_playerWeaponType")))
    local game_object = get_game_object(player)
    state.game_object_type = type_name(game_object)
    state.effect_components = inspect_effect_components(game_object)

    if state.weapon_type ~= SWORD_AND_SHIELD_WEAPON_TYPE
        or state.player_type ~= SWORD_AND_SHIELD_PLAYER_TYPE then
        state.status = "player available; equip Sword & Shield; weapon=" .. tostring(state.weapon_type)
        state.last_key = nil
        return
    end

    local node_id, node_name = read_motion(player, player_type)
    if node_id == nil then
        state.status = "Sword & Shield available; motion node unavailable"
        return
    end

    state.status = "observing Sword & Shield action transitions"
    local key = tostring(node_id) .. ":" .. tostring(node_name)
    if key == state.last_key then return end
    state.last_key = key
    state.sequence = state.sequence + 1
    state.events[#state.events + 1] = {
        sequence = state.sequence,
        frame = state.frame,
        node_id = node_id,
        node_name = node_name,
    }
    if #state.events > MAX_EVENTS then table.remove(state.events, 1) end
    state.dirty = true
end

re.on_frame(function()
    state.frame = state.frame + 1
    if state.frame % SAMPLE_INTERVAL_FRAMES == 0 then capture() end
    if state.frame % HEARTBEAT_INTERVAL_FRAMES == 0 then state.dirty = true end
    persist()
end)

return M
