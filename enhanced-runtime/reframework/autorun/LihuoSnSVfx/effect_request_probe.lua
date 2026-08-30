local M = {}

local OUTPUT_PATH = "LihuoSnSVfx-effect-requests.json"
local EXPECTED_PLAYER_TYPE = "snow.player.ShortSword"
local EXPECTED_WEAPON_TYPE = 8
local MAX_EVENTS = 1024

local state = {
    frame = 0,
    target_manager_address = nil,
    target_motion_node_id = nil,
    target_motion_node_name = nil,
    hooked = false,
    hook_error = nil,
    events = {},
    pending = {},
    dirty = true,
}

local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value, nil end
    return nil, tostring(value)
end

local function primitive(value)
    if value == nil then return nil end
    if type(value) == "number" then return value end
    local converted = safe(function() return sdk.to_int64(value) end)
    return tonumber(converted) or tostring(converted)
end

local function type_name(value)
    local definition = value and safe(function() return value:get_type_definition() end) or nil
    return definition and safe(function() return definition:get_full_name() end) or nil
end

local function address_of(value)
    local address = value and safe(function() return value:get_address() end) or nil
    return address and tostring(address) or nil
end

local function find_player()
    local manager = safe(function() return sdk.get_managed_singleton("snow.player.PlayerManager") end)
    local definition = manager and safe(function() return manager:get_type_definition() end) or nil
    local method = definition and safe(function() return definition:get_method("findMasterPlayer") end) or nil
    return method and safe(function() return method:call(manager) end) or nil
end

local function weapon_type(player)
    local definition = player and safe(function() return player:get_type_definition() end) or nil
    local field = definition and safe(function() return definition:get_field("_playerWeaponType") end) or nil
    local value = field and safe(function() return field:get_data(player) end) or nil
    return tonumber(value and safe(function() return value.value__ end) or value)
end

local function game_object(player)
    return player and (safe(function() return player:call("get_GameObject") end)
        or safe(function() return player:call("getGameObject") end)) or nil
end

local function object_effect_manager(player)
    local object = game_object(player)
    local component_type = safe(function() return sdk.typeof("via.effect.script.ObjectEffectManager") end)
    return object and component_type and safe(function()
        return object:call("getComponent(System.Type)", component_type)
    end) or nil
end

local function read_motion(player)
    local definition = player and safe(function() return player:get_type_definition() end) or nil
    local getter = definition and safe(function() return definition:get_method("getMotionFsm2") end) or nil
    local motion = getter and safe(function() return getter:call(player) end) or nil
    local motion_type = motion and safe(function() return motion:get_type_definition() end) or nil
    local current = motion_type and safe(function()
        return motion_type:get_method("getCurrentNodeID(System.Int32)")
            or motion_type:get_method("getCurrentNodeID")
    end) or nil
    local node_id = current and tonumber(primitive(safe(function() return current:call(motion, 0) end))) or nil
    if node_id == nil then return nil, nil end
    local layer = safe(function() return motion:call("getLayer", 0) end)
    local tree = layer and safe(function() return layer:get_tree_object() end) or nil
    local node = tree and safe(function() return tree:get_node(node_id) end) or nil
    return node_id, node and safe(function() return node:get_name() end) or nil
end

local function enqueue(route, overload, args)
    local instance = safe(function() return sdk.to_managed_object(args[2]) end)
    local address = address_of(instance)
    if address == nil or address ~= state.target_manager_address then return end
    local event = {
        frame = state.frame,
        route = route,
        overload = overload,
        manager_address = address,
        motion_node_id = state.target_motion_node_id,
        motion_node_name = state.target_motion_node_name,
        container_id = primitive(args[3]),
    }
    if overload == 3 then
        event.element_id = primitive(args[4])
        event.external_index = primitive(args[5])
    else
        event.external_index = primitive(args[4])
    end
    state.pending[#state.pending + 1] = event
end

local function install_hook(signature, route, overload)
    local definition = sdk.find_type_definition("via.effect.script.ObjectEffectManager")
    local method = definition and definition:get_method(signature) or nil
    if method == nil then return false, "missing overload: " .. signature end
    sdk.hook(method, function(args)
        enqueue(route, overload, args)
    end, function(retval)
        return retval
    end)
    return true, nil
end

local function install_hooks()
    local ok_three, error_three = safe(function()
        local ok, reason = install_hook(
            "requestEffectFromFsm(System.UInt32, System.UInt32, System.Int32)",
            "requestEffectFromFsm", 3
        )
        if not ok then error(reason) end
        return true
    end)
    local ok_two, error_two = safe(function()
        local ok, reason = install_hook(
            "requestEffectFromFsm(System.UInt32, System.Int32)",
            "requestEffectFromFsm", 2
        )
        if not ok then error(reason) end
        return true
    end)
    local ok_sequence, error_sequence = safe(function()
        local ok, reason = install_hook(
            "requestEffectFromFsmOrSequence(System.UInt32, System.UInt32, System.Int32)",
            "requestEffectFromFsmOrSequence", 3
        )
        if not ok then error(reason) end
        return true
    end)
    state.hooked = ok_three == true and ok_two == true and ok_sequence == true
    if not state.hooked then
        state.hook_error = table.concat({
            tostring(error_three or ""),
            tostring(error_two or ""),
            tostring(error_sequence or ""),
        }, "; ")
    end
    state.dirty = true
end

local function update_target()
    local player = find_player()
    if player == nil or type_name(player) ~= EXPECTED_PLAYER_TYPE or weapon_type(player) ~= EXPECTED_WEAPON_TYPE then
        state.target_manager_address = nil
        state.target_motion_node_id = nil
        state.target_motion_node_name = nil
        return
    end
    state.target_manager_address = address_of(object_effect_manager(player))
    state.target_motion_node_id, state.target_motion_node_name = read_motion(player)
end

local function flush()
    for _, event in ipairs(state.pending) do
        state.events[#state.events + 1] = event
        if #state.events > MAX_EVENTS then table.remove(state.events, 1) end
        state.dirty = true
    end
    state.pending = {}
    if not state.dirty then return end
    local status = state.hooked and "recording player ObjectEffectManager requests"
        or "hook installation failed"
    local written = safe(function()
        json.dump_file(OUTPUT_PATH, {
            schema_version = 1,
            policy = "read_only_player_object_effect_request_hook",
            status = status,
            hook_error = state.hook_error,
            frame = state.frame,
            target_manager_address = state.target_manager_address,
            event_count = #state.events,
            events = state.events,
        })
        return true
    end)
    if written then state.dirty = false end
end

install_hooks()

re.on_frame(function()
    state.frame = state.frame + 1
    update_target()
    if state.frame % 120 == 0 then state.dirty = true end
    flush()
end)

return M
