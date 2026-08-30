local OUTPUT_PATH = "LihuoSnSVfx-effect-metadata.json"
local MAX_MEMBERS = 160
local MAX_FRAMES = 900

local exact_types = {
    "via.effect.script.EffectManager",
    "via.effect.script.ObjectEffectManager",
    "via.effect.script.ObjectEffectManager2",
    "via.effect.script.CreatedEffectContainer",
    "via.effect.script.EnvironmentEffectManager",
    "via.effect.ProviderData",
    "via.effect.EffectResource",
    "via.effect.EffectResourceHolder",
    "snow.EnvironmentEffectManagerHelper",
}

local terms = { "effect", "epv", "request", "create", "play", "stop" }
local frame = 0
local written = false

local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function type_name(value)
    if value == nil then return nil end
    return safe(function() return value:get_full_name() end)
        or safe(function() return value:get_name() end)
end

local function mentions(value)
    local text = string.lower(tostring(value or ""))
    for _, term in ipairs(terms) do
        if string.find(text, term, 1, true) then return true end
    end
    return false
end

local function method_contract(method)
    local names = safe(function() return method:get_param_names() end) or {}
    local params = {}
    for index, param_type in ipairs(safe(function() return method:get_param_types() end) or {}) do
        params[#params + 1] = {
            index = index - 1,
            name = names[index],
            type = type_name(param_type),
            is_by_ref = safe(function() return param_type:is_by_ref() end) == true,
        }
    end
    return {
        name = safe(function() return method:get_name() end),
        return_type = type_name(safe(function() return method:get_return_type() end)),
        is_static = safe(function() return method:is_static() end) == true,
        params = params,
    }
end

local function type_contract(type_definition)
    local result = {
        type = type_name(type_definition),
        available = type_definition ~= nil,
        methods = {},
        fields = {},
    }
    if type_definition == nil then return result end

    for _, method in ipairs(safe(function() return type_definition:get_methods() end) or {}) do
        local contract = method_contract(method)
        local signature = tostring(contract.name) .. " " .. tostring(contract.return_type)
        for _, param in ipairs(contract.params) do signature = signature .. " " .. tostring(param.type) end
        if mentions(signature) then
            result.methods[#result.methods + 1] = contract
            if #result.methods >= MAX_MEMBERS then result.methods_truncated = true break end
        end
    end
    for _, field in ipairs(safe(function() return type_definition:get_fields() end) or {}) do
        local name = safe(function() return field:get_name() end)
        local field_type = type_name(safe(function() return field:get_type() end))
        if mentions(name) or mentions(field_type) then
            result.fields[#result.fields + 1] = {
                name = name,
                type = field_type,
                is_static = safe(function() return field:is_static() end) == true,
            }
            if #result.fields >= MAX_MEMBERS then result.fields_truncated = true break end
        end
    end
    return result
end

local function find_player()
    local manager = safe(function() return sdk.get_managed_singleton("snow.player.PlayerManager") end)
    local manager_type = manager and safe(function() return manager:get_type_definition() end) or nil
    local method = manager_type and safe(function() return manager_type:get_method("findMasterPlayer") end) or nil
    return method and safe(function() return method:call(manager) end) or nil
end

local function write_report(status, player)
    local contracts = {}
    for _, name in ipairs(exact_types) do
        contracts[#contracts + 1] = type_contract(safe(function() return sdk.find_type_definition(name) end))
    end
    if player ~= nil then
        local current = safe(function() return player:get_type_definition() end)
        local depth = 0
        while current ~= nil and depth < 8 do
            contracts[#contracts + 1] = type_contract(current)
            current = safe(function() return current:get_parent_type() end)
            depth = depth + 1
        end
    end
    json.dump_file(OUTPUT_PATH, {
        schema_version = 1,
        policy = "exact_named_types_metadata_only_no_gameplay_calls",
        status = status,
        frame = frame,
        contracts = contracts,
    })
    written = true
end

re.on_frame(function()
    if written then return end
    frame = frame + 1
    if frame < 60 then return end
    local player = find_player()
    if player ~= nil then write_report("player available", player) return end
    if frame >= MAX_FRAMES then write_report("player unavailable; exact types only", nil) end
end)
