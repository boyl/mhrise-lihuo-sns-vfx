local M = {}

local OUTPUT_PATH = "LihuoSnSVfx-dispatch-probe.json"
local RESOURCE_PATH = "vfx/editor/efd_pl/efd_s-swd/efd_0004_s-swd_10_0200.efx"
local EXPECTED_PLAYER_TYPE = "snow.player.ShortSword"
local EXPECTED_WEAPON_TYPE = 8
local WAIT_FRAMES_AFTER_PLAYER = 180

local state = {
    frame = 0,
    ready_frame = nil,
    attempted = false,
    status = "loaded; waiting for Sword & Shield player",
}

local retained = {}

local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value, nil end
    return nil, tostring(value)
end

local function type_name(value)
    local definition = value and safe(function() return value:get_type_definition() end) or nil
    return definition and safe(function() return definition:get_full_name() end) or nil
end

local function primitive(value)
    if value == nil then return nil end
    if type(value) == "number" then return value end
    return safe(function() return value.value__ end)
end

local function find_player()
    local manager = safe(function() return sdk.get_managed_singleton("snow.player.PlayerManager") end)
    local method = manager and safe(function() return manager:get_type_definition():get_method("findMasterPlayer") end) or nil
    return method and safe(function() return method:call(manager) end) or nil
end

local function weapon_type(player)
    local definition = safe(function() return player:get_type_definition() end)
    local field = definition and safe(function() return definition:get_field("_playerWeaponType") end) or nil
    return tonumber(primitive(field and safe(function() return field:get_data(player) end) or nil))
end

local function write_report(extra)
    local payload = {
        schema_version = 1,
        policy = "single_bounded_visible_effect_dispatch",
        frame = state.frame,
        status = state.status,
        attempted = state.attempted,
        resource_path = RESOURCE_PATH,
    }
    for key, value in pairs(extra or {}) do payload[key] = value end
    safe(function() json.dump_file(OUTPUT_PATH, payload) end)
end

local function dispatch(player)
    state.attempted = true
    local game_object = safe(function() return player:call("get_GameObject") end)
    local transform = game_object and safe(function() return game_object:call("get_Transform") end) or nil
    local position = transform and safe(function() return transform:call("get_Position") end) or nil
    local rotation = transform and safe(function() return transform:call("get_Rotation") end) or nil
    local resource, resource_error = safe(function()
        local value = sdk.create_resource("via.effect.EffectResource", RESOURCE_PATH)
        if value ~= nil then value:add_ref() end
        return value
    end)
    local holder, holder_error = resource and safe(function()
        local value = resource:create_holder("via.effect.EffectResourceHolder")
        if value ~= nil then value:add_ref() end
        return value
    end) or nil
    local provider, provider_error = safe(function()
        local value = sdk.create_instance("via.effect.ProviderData")
        if value ~= nil then value:add_ref() end
        return value
    end)
    local manager = safe(function()
        return sdk.get_managed_singleton("via.effect.script.EffectManager")
    end)

    local missing = {}
    if game_object == nil then missing[#missing + 1] = "game_object" end
    if position == nil then missing[#missing + 1] = "position" end
    if rotation == nil then missing[#missing + 1] = "rotation" end
    if resource == nil then missing[#missing + 1] = "resource:" .. tostring(resource_error) end
    if holder == nil then missing[#missing + 1] = "holder:" .. tostring(holder_error) end
    if provider == nil then missing[#missing + 1] = "provider:" .. tostring(provider_error) end
    if manager == nil then missing[#missing + 1] = "effect_manager" end
    if #missing > 0 then
        state.status = "dispatch prerequisites unavailable"
        write_report({ missing = missing })
        return
    end

    retained.resource = resource
    retained.holder = holder
    retained.provider = provider
    local _, set_error = safe(function() provider:call("setResources", 0, holder) end)
    if set_error ~= nil then
        state.status = "provider resource binding failed"
        write_report({ error = set_error })
        return
    end
    local extern_params = safe(function() return provider:call("createExternParameter", 0) end)
    local manager_type = safe(function() return manager:get_type_definition() end)
    local method = manager_type and safe(function()
        return manager_type:get_method(
            "createEffectAutoDestroy(via.GameObject, via.effect.ProviderData, via.vec3, via.Quaternion, via.GameObject, System.String, via.effect.ExternParameter[])"
        )
    end) or nil
    if method == nil then
        state.status = "exact dispatch overload unavailable"
        write_report()
        return
    end

    local container, call_error = safe(function()
        return method:call(manager, game_object, provider, position, rotation, game_object, "", extern_params)
    end)
    retained.container = container
    if container == nil then
        state.status = "dispatch call returned no effect"
        write_report({ error = call_error })
        return
    end
    state.status = "dispatch call succeeded"
    write_report({ container_type = type_name(container) })
end

re.on_frame(function()
    state.frame = state.frame + 1
    if state.attempted or state.frame % 2 ~= 0 then return end
    local player = find_player()
    if player == nil or type_name(player) ~= EXPECTED_PLAYER_TYPE or weapon_type(player) ~= EXPECTED_WEAPON_TYPE then
        if state.frame % 120 == 0 then write_report() end
        return
    end
    if state.ready_frame == nil then
        state.ready_frame = state.frame
        state.status = "Sword & Shield ready; dispatch scheduled"
        write_report()
        return
    end
    if state.frame - state.ready_frame >= WAIT_FRAMES_AFTER_PLAYER then dispatch(player) end
end)

re.on_script_reset(function()
    retained = {}
end)

return M
