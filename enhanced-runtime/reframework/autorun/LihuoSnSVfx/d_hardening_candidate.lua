local M = {}

local CONFIG_PATH = "LihuoSnSVfx-d-hardening.json"
local OUTPUT_PATH = "LihuoSnSVfx-d-hardening-result.json"
local EXPECTED_WEAPON_TYPE = 8
local EXPECTED_ACTION_BANK = 100
local EXPECTED_CONTAINER_ID = 150
local HIT_SOURCE_SIGNATURE = "afterCalcDamage_DamageSide(snow.hit.DamageFlowInfoBase,snow.DamageReceiver.HitInfo)"
local VALID_TIERS = { normal = true, finisher = true, signature = true }
local PERSISTENT_EFFECT_IDS = {
    [24021] = true, [24022] = true, [24044] = true,
    [24049] = true, [24050] = true, [24051] = true,
}

local HIT_SOURCE_SHAPE = {
    name = "afterCalcDamage_DamageSide",
    declaring_type = "snow.enemy.EnemyCharacterBase",
    is_static = false,
    parameter_types = {"snow.hit.DamageFlowInfoBase", "snow.DamageReceiver.HitInfo"},
    return_type = "System.Void",
}

local state = {
    tick = 0,
    active = false,
    status = "loading configuration",
    config = nil,
    yun = nil,
    hook_installed = false,
    effects_ready = false,
    recipes = {},
    recipe_count = 0,
    recipe_audit_complete = false,
    valid_recipe_count = 0,
    current_action_key = nil,
    current_action_serial = 0,
    current_action_eligible = false,
    current_recipe = nil,
    current_action_frame = nil,
    last_action_frame = nil,
    last_eligible_action_tick = nil,
    last_eligible_action_serial = nil,
    last_eligible_recipe = nil,
    last_whiff_action_serial = -1,
    current_hit_count = 0,
    active_instances = {},
    active_instance_action_serial = nil,
    active_instance_recipe = nil,
    instance_dispatches = 0,
    instance_releases = 0,
    instance_release_failures = 0,
    last_instance_release_reason = nil,
    whiff_attempts = 0,
    whiff_successes = 0,
    hit_hook_calls = 0,
    hit_attempts = 0,
    hit_successes = 0,
    hit_rejection_counts = {},
    last_hit_rejection = nil,
    last_hit_observation = nil,
    dispatch_by_tier = { normal = 0, finisher = 0, signature = 0 },
    invalid_effect_ids = {},
    last_error = nil,
    dirty = true,
}

local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value, nil end
    return nil, tostring(value)
end

local function number_call(fn)
    local value = safe(fn)
    return tonumber(value)
end

local function exact_integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function validate_config(config)
    if type(config) ~= "table" or config.schema_version ~= 2 then
        return false, "unsupported or missing configuration"
    end
    if config.enabled ~= true then return false, "candidate must be explicitly enabled by package" end
    if config.weapon_type ~= EXPECTED_WEAPON_TYPE then return false, "weapon_type must be 8" end
    if config.action_bank ~= EXPECTED_ACTION_BANK then return false, "action_bank must be 100" end
    if config.container_id ~= EXPECTED_CONTAINER_ID then return false, "container_id must be 150" end
    if config.network_sync ~= false then return false, "network_sync must be false" end
    if not exact_integer(config.default_whiff_trigger_frame, 0, 30)
        or not exact_integer(config.default_whiff_max_late_frames, 0, 15) then
        return false, "invalid whiff frame window"
    end
    if not exact_integer(config.hit_grace_ticks, 0, 30) then return false, "invalid hit grace window" end
    if type(config.recipes) ~= "table" or #config.recipes < 20 then
        return false, "full-action recipe set is missing"
    end
    local seen = {}
    for _, recipe in ipairs(config.recipes) do
        if type(recipe) ~= "table" or not exact_integer(recipe.action_id, 1, 999)
            or type(recipe.name) ~= "string" or recipe.name == ""
            or VALID_TIERS[recipe.tier] ~= true
            or not exact_integer(recipe.whiff_effect_id, 1, 999999)
            or not exact_integer(recipe.hit_effect_id, 1, 999999)
            or not exact_integer(recipe.max_hit_effects, 1, 8) then
            return false, "invalid action recipe"
        end
        if recipe.whiff_mode ~= "one_shot" and recipe.whiff_mode ~= "instance" then
            return false, "invalid whiff lifecycle mode"
        end
        if PERSISTENT_EFFECT_IDS[recipe.hit_effect_id]
            or (recipe.whiff_mode == "one_shot" and PERSISTENT_EFFECT_IDS[recipe.whiff_effect_id])
            or (recipe.whiff_mode == "instance" and not PERSISTENT_EFFECT_IDS[recipe.whiff_effect_id])
            or (recipe.finish_effect_id ~= nil and (not exact_integer(recipe.finish_effect_id, 1, 999999)
                or PERSISTENT_EFFECT_IDS[recipe.finish_effect_id])) then
            return false, "effect lifecycle does not match recipe mode"
        end
        local key = tostring(EXPECTED_ACTION_BANK) .. ":" .. tostring(recipe.action_id)
        if seen[key] then return false, "duplicate action recipe " .. key end
        seen[key] = true
    end
    return true, nil
end

local function persist()
    if not state.dirty then return end
    local config = state.config
    local written = safe(function()
        json.dump_file(OUTPUT_PATH, {
            schema_version = 2,
            policy = "d_provider_local_only_full_sns_recipe_exact_hit",
            tick = state.tick,
            active = state.active,
            status = state.status,
            hook_installed = state.hook_installed,
            effects_ready = state.effects_ready,
            weapon_type = config and config.weapon_type or nil,
            action_bank = config and config.action_bank or nil,
            container_id = config and config.container_id or nil,
            recipe_count = state.recipe_count,
            recipe_audit_complete = state.recipe_audit_complete,
            valid_recipe_count = state.valid_recipe_count,
            network_sync = false,
            hit_source_signature = HIT_SOURCE_SIGNATURE,
            current_action_key = state.current_action_key,
            current_action_serial = state.current_action_serial,
            current_action_eligible = state.current_action_eligible,
            current_recipe_name = state.current_recipe and state.current_recipe.name or nil,
            current_recipe_tier = state.current_recipe and state.current_recipe.tier or nil,
            current_action_frame = state.current_action_frame,
            last_eligible_action_tick = state.last_eligible_action_tick,
            last_eligible_action_serial = state.last_eligible_action_serial,
            whiff_attempts = state.whiff_attempts,
            whiff_successes = state.whiff_successes,
            instance_dispatches = state.instance_dispatches,
            instance_releases = state.instance_releases,
            instance_release_failures = state.instance_release_failures,
            active_instance_count = #state.active_instances,
            active_instance_action_serial = state.active_instance_action_serial,
            active_instance_recipe_name = state.active_instance_recipe and state.active_instance_recipe.name or nil,
            last_instance_release_reason = state.last_instance_release_reason,
            hit_hook_calls = state.hit_hook_calls,
            hit_attempts = state.hit_attempts,
            hit_successes = state.hit_successes,
            hit_rejection_counts = state.hit_rejection_counts,
            last_hit_rejection = state.last_hit_rejection,
            last_hit_observation = state.last_hit_observation,
            dispatch_by_tier = state.dispatch_by_tier,
            invalid_effect_ids = state.invalid_effect_ids,
            last_error = state.last_error,
        })
        return true
    end)
    if written == true then state.dirty = false end
end

local config, config_error = safe(function() return json.load_file(CONFIG_PATH) end)
local config_valid, validation_error = validate_config(config)
if not config_valid then
    state.status = "disabled: " .. tostring(validation_error or config_error)
    state.last_error = validation_error or config_error
    persist()
    return M
end
state.config = config
for _, recipe in ipairs(config.recipes) do
    local key = tostring(EXPECTED_ACTION_BANK) .. ":" .. tostring(recipe.action_id)
    state.recipes[key] = recipe
    state.recipe_count = state.recipe_count + 1
end

local yun, dependency_error = safe(function() return require("yunwulian.yun_modules") end)
local required_yun_members = {
    "get_master_player", "get_master_player_index", "get_weapon_type",
    "get_action_id", "get_action_bank_id", "get_now_action_frame",
    "is_effect_exists", "set_effect", "set_effect_with_instance",
}
if yun == nil then
    state.status = "disabled: yun_modules dependency unavailable"
    state.last_error = dependency_error
    persist()
    return M
end
for _, name in ipairs(required_yun_members) do
    if type(yun[name]) ~= "function" then
        state.status = "disabled: incompatible yun_modules API"
        state.last_error = "missing " .. name
        persist()
        return M
    end
end
if type(yun.weapon_type) ~= "table" or yun.weapon_type.ShortSword ~= EXPECTED_WEAPON_TYPE then
    state.status = "disabled: yun_modules weapon identity mismatch"
    state.last_error = "weapon_type.ShortSword must be 8"
    persist()
    return M
end
state.yun = yun

local function exact_type(name)
    return safe(function() return sdk.find_type_definition(name) end)
end

local function type_full_name(type_definition)
    if type_definition == nil then return nil end
    return safe(function() return type_definition:get_full_name() end)
        or safe(function() return type_definition:get_name() end)
end

local function method_matches_shape(method, shape)
    if method == nil or safe(function() return method:get_name() end) ~= shape.name then return false end
    if safe(function() return method:is_static() end) ~= shape.is_static then return false end
    if type_full_name(safe(function() return method:get_return_type() end)) ~= shape.return_type then return false end
    local parameter_types = safe(function() return method:get_param_types() end)
    if parameter_types == nil or #parameter_types ~= #shape.parameter_types then return false end
    for index, expected in ipairs(shape.parameter_types) do
        if type_full_name(parameter_types[index]) ~= expected then return false end
        if safe(function() return parameter_types[index]:is_by_ref() end) == true then return false end
    end
    return true
end

local function resolve_unique_method(owner_type, shape)
    if owner_type == nil then return nil, "missing owner type" end
    local methods, methods_error = safe(function() return owner_type:get_methods() end)
    if methods == nil then return nil, methods_error or "cannot enumerate hit method" end
    local matches = {}
    for _, method in ipairs(methods) do
        if method_matches_shape(method, shape) then matches[#matches + 1] = method end
    end
    if #matches ~= 1 then return nil, "exact hit shape count=" .. tostring(#matches) end
    return matches[1], nil
end

local contracts = {
    enemy_type = exact_type("snow.enemy.EnemyCharacterBase"),
    damage_type = exact_type("snow.hit.DamageFlowInfoBase"),
    hit_info_type = exact_type("snow.DamageReceiver.HitInfo"),
    short_sword_type = exact_type("snow.player.ShortSword"),
}
contracts.hit_source_method, contracts.hit_source_error = resolve_unique_method(
    contracts.enemy_type, HIT_SOURCE_SHAPE)
for _, name in ipairs({"enemy_type", "damage_type", "hit_info_type", "short_sword_type", "hit_source_method"}) do
    if contracts[name] == nil then
        state.status = "disabled: exact tdb71 reflection contract unavailable"
        state.last_error = name == "hit_source_method" and contracts.hit_source_error or ("missing " .. name)
        persist()
        return M
    end
end

local function is_a(value, expected)
    if value == nil or expected == nil then return false end
    local actual = safe(function() return value:get_type_definition() end)
    return actual ~= nil and safe(function() return actual:is_a(expected) end) == true
end

local function refresh_effect_readiness()
    if state.tick % 60 == 1 and type(yun.clear_effect_validity_cache) == "function" then
        safe(function() yun.clear_effect_validity_cache() end)
    end
    -- Motion108 是已完成实机验收的基准配方；启动时以它证明完整 Provider 闭包可用。
    local baseline = state.recipes["100:108"]
    if baseline == nil then return false end
    local whiff_exists = safe(function()
        return yun.is_effect_exists(EXPECTED_CONTAINER_ID, baseline.whiff_effect_id)
    end)
    local hit_exists = safe(function()
        return yun.is_effect_exists(EXPECTED_CONTAINER_ID, baseline.hit_effect_id)
    end)
    state.effects_ready = whiff_exists == true and hit_exists == true
    if state.effects_ready and not state.recipe_audit_complete then
        local valid_count = 0
        for _, recipe in pairs(state.recipes) do
            local whiff_ok = safe(function()
                return yun.is_effect_exists(EXPECTED_CONTAINER_ID, recipe.whiff_effect_id)
            end) == true
            local hit_ok = safe(function()
                return yun.is_effect_exists(EXPECTED_CONTAINER_ID, recipe.hit_effect_id)
            end) == true
            local finish_ok = recipe.finish_effect_id == nil or safe(function()
                return yun.is_effect_exists(EXPECTED_CONTAINER_ID, recipe.finish_effect_id)
            end) == true
            if whiff_ok and hit_ok and finish_ok then
                valid_count = valid_count + 1
            else
                if not whiff_ok then state.invalid_effect_ids[tostring(recipe.whiff_effect_id)] = true end
                if not hit_ok then state.invalid_effect_ids[tostring(recipe.hit_effect_id)] = true end
                if not finish_ok then state.invalid_effect_ids[tostring(recipe.finish_effect_id)] = true end
            end
        end
        state.valid_recipe_count = valid_count
        state.recipe_audit_complete = true
        state.dirty = true
    end
    if state.effects_ready then
        state.status = "armed locally; D provider pair verified"
        state.dirty = true
    end
    return state.effects_ready
end

local function dispatch_local(effect_id, role, recipe)
    if not refresh_effect_readiness() then
        state.status = role .. " dispatch blocked: baseline provider pair unavailable"
        state.last_error = "is_effect_exists did not verify baseline 150:24007 and 150:30007"
        state.dirty = true
        return false
    end
    local effect_exists = safe(function()
        return yun.is_effect_exists(EXPECTED_CONTAINER_ID, effect_id)
    end)
    if effect_exists ~= true then
        state.invalid_effect_ids[tostring(effect_id)] = true
        state.status = role .. " dispatch skipped: effect unavailable"
        state.last_error = "effect unavailable: 150:" .. tostring(effect_id)
        state.dirty = true
        return false
    end
    local result, call_error = safe(function()
        return yun.set_effect(EXPECTED_CONTAINER_ID, effect_id, false)
    end)
    if result ~= true then
        state.status = role .. " dispatch failed closed"
        state.last_error = call_error or "set_effect returned non-true"
        log.error("[LihuoSnSVfx:DHardening] " .. state.status .. ": " .. tostring(state.last_error))
        state.dirty = true
        return false
    end
    state.status = role .. " local effect dispatched"
    state.last_error = nil
    if recipe and VALID_TIERS[recipe.tier] then
        state.dispatch_by_tier[recipe.tier] = state.dispatch_by_tier[recipe.tier] + 1
    end
    log.info("[LihuoSnSVfx:DHardening] " .. state.status)
    state.dirty = true
    return true
end

local function release_active_instances(reason)
    if #state.active_instances == 0 then return true end
    local released = 0
    local failed = 0
    local finish_effect_id = state.active_instance_recipe and state.active_instance_recipe.finish_effect_id or nil
    local finish_recipe = state.active_instance_recipe
    for _, instance in ipairs(state.active_instances) do
        local ok = pcall(function()
            instance:finishAll()
            instance:force_release()
        end)
        if ok then released = released + 1 else failed = failed + 1 end
    end
    state.active_instances = {}
    state.active_instance_action_serial = nil
    state.active_instance_recipe = nil
    state.instance_releases = state.instance_releases + released
    state.instance_release_failures = state.instance_release_failures + failed
    state.last_instance_release_reason = reason
    state.status = failed == 0 and "persistent effect released" or "persistent effect release partially failed"
    state.last_error = failed == 0 and nil or ("instance release failures=" .. tostring(failed))
    state.dirty = true
    if finish_effect_id ~= nil then
        dispatch_local(finish_effect_id, "finish", finish_recipe)
    end
    return failed == 0
end

local function dispatch_local_instance(effect_id, role, recipe)
    if not refresh_effect_readiness() then
        state.status = role .. " instance blocked: baseline provider pair unavailable"
        state.last_error = "is_effect_exists did not verify baseline 150:24007 and 150:30007"
        state.dirty = true
        return false
    end
    local effect_exists = safe(function()
        return yun.is_effect_exists(EXPECTED_CONTAINER_ID, effect_id)
    end)
    if effect_exists ~= true then
        state.invalid_effect_ids[tostring(effect_id)] = true
        state.status = role .. " instance skipped: effect unavailable"
        state.last_error = "effect unavailable: 150:" .. tostring(effect_id)
        state.dirty = true
        return false
    end
    release_active_instances("replace-before-instance-dispatch")
    local instance, call_error = safe(function()
        return yun.set_effect_with_instance(EXPECTED_CONTAINER_ID, effect_id, false)
    end)
    if instance == nil or instance == false then
        state.status = role .. " instance dispatch failed closed"
        state.last_error = call_error or "set_effect_with_instance returned nil"
        log.error("[LihuoSnSVfx:DHardening] " .. state.status .. ": " .. tostring(state.last_error))
        state.dirty = true
        return false
    end
    state.active_instances[#state.active_instances + 1] = instance
    state.active_instance_action_serial = state.current_action_serial
    state.active_instance_recipe = recipe
    state.instance_dispatches = state.instance_dispatches + 1
    state.status = role .. " persistent local effect dispatched"
    state.last_error = nil
    if recipe and VALID_TIERS[recipe.tier] then
        state.dispatch_by_tier[recipe.tier] = state.dispatch_by_tier[recipe.tier] + 1
    end
    log.info("[LihuoSnSVfx:DHardening] " .. state.status)
    state.dirty = true
    return true
end

local function reject_hit(reason)
    state.last_hit_rejection = reason
    state.hit_rejection_counts[reason] = (state.hit_rejection_counts[reason] or 0) + 1
    state.dirty = true
end

local function eligible_hit_context()
    if state.current_action_eligible then
        return state.current_action_serial, state.current_recipe
    end
    if state.last_eligible_action_tick ~= nil
        and state.last_eligible_action_serial ~= nil
        and state.tick - state.last_eligible_action_tick <= config.hit_grace_ticks then
        return state.last_eligible_action_serial, state.last_eligible_recipe
    end
    return nil, nil
end

local function pre_hit(args)
    if not state.active then return end
    state.hit_hook_calls = state.hit_hook_calls + 1
    state.dirty = true

    local action_serial, recipe = eligible_hit_context()
    if action_serial == nil or recipe == nil then reject_hit("configured-action-not-current-or-recent") return end
    if state.current_hit_count >= recipe.max_hit_effects then reject_hit("action-hit-limit-reached") return end

    local enemy = sdk.to_managed_object(args[2])
    local calc_result = sdk.to_managed_object(args[3])
    local hit_info = sdk.to_managed_object(args[4])
    local master_player = safe(function() return yun.get_master_player() end)
    local player_index = number_call(function() return yun.get_master_player_index() end)
    local damage_attacker_id = number_call(function() return calc_result:get_AttackerID() end)
    local damage_weapon_type = number_call(function() return calc_result:get_WeaponType() end)
    state.last_hit_observation = {
        action_serial = action_serial,
        recipe_name = recipe.name,
        recipe_tier = recipe.tier,
        ticks_since_eligible_action = state.last_eligible_action_tick
            and (state.tick - state.last_eligible_action_tick) or nil,
        master_player_index = player_index,
        damage_attacker_id = damage_attacker_id,
        damage_weapon_type = damage_weapon_type,
    }

    if not is_a(enemy, contracts.enemy_type) then reject_hit("enemy-type-mismatch") return end
    if not is_a(calc_result, contracts.damage_type) then reject_hit("damage-type-mismatch") return end
    if not is_a(hit_info, contracts.hit_info_type) then reject_hit("hit-info-type-mismatch") return end
    if not is_a(master_player, contracts.short_sword_type) then reject_hit("master-player-not-sns") return end
    if not exact_integer(player_index, 0, 255)
        or not exact_integer(damage_attacker_id, 0, 255)
        or not exact_integer(damage_weapon_type, 0, 255) then
        reject_hit("hit-authentication-unavailable") return
    end
    if damage_attacker_id ~= player_index then reject_hit("attacker-id-mismatch") return end
    if damage_weapon_type ~= EXPECTED_WEAPON_TYPE then reject_hit("damage-weapon-type-mismatch") return end
    if number_call(function() return yun.get_weapon_type() end) ~= EXPECTED_WEAPON_TYPE then
        reject_hit("current-weapon-type-mismatch") return
    end

    state.hit_attempts = state.hit_attempts + 1
    if dispatch_local(recipe.hit_effect_id, "hit", recipe) then
        state.current_hit_count = state.current_hit_count + 1
        state.hit_successes = state.hit_successes + 1
    end
end

local hook_ok, hook_error = safe(function()
    sdk.hook(contracts.hit_source_method, pre_hit)
    return true
end)
if hook_ok ~= true then
    state.status = "disabled: exact hit hook registration failed"
    state.last_error = hook_error
    persist()
    return M
end
state.hook_installed = true
state.active = true
state.status = "armed locally; waiting for D provider pair"
log.info("[LihuoSnSVfx:DHardening] " .. state.status)

re.on_pre_application_entry("UpdateScene", function()
    state.tick = state.tick + 1
    if not state.active then persist() return end
    refresh_effect_readiness()

    local weapon_type = number_call(function() return yun.get_weapon_type() end)
    local action_bank = number_call(function() return yun.get_action_bank_id() end)
    local action_id = number_call(function() return yun.get_action_id() end)
    local action_frame = number_call(function() return yun.get_now_action_frame() end)
    local key = tostring(action_bank) .. ":" .. tostring(action_id)
    local recipe = state.recipes[key]
    local eligible = weapon_type == EXPECTED_WEAPON_TYPE
        and action_bank == EXPECTED_ACTION_BANK
        and recipe ~= nil
        and action_frame ~= nil
    local action_key = tostring(weapon_type) .. ":" .. key
    local current_frame = action_frame and math.floor(action_frame) or nil
    local action_changed = action_key ~= state.current_action_key
    local action_restarted = eligible and not action_changed and state.last_action_frame ~= nil
        and current_frame < state.last_action_frame
    if action_changed or action_restarted then
        release_active_instances(action_changed and "action-changed" or "action-restarted")
        state.current_action_key = action_key
        if eligible then
            state.current_action_serial = state.current_action_serial + 1
            state.last_whiff_action_serial = -1
            state.current_hit_count = 0
        end
        state.dirty = true
    end
    state.current_action_eligible = eligible
    state.current_recipe = eligible and recipe or nil
    state.current_action_frame = current_frame
    if eligible then
        state.last_eligible_action_tick = state.tick
        state.last_eligible_action_serial = state.current_action_serial
        state.last_eligible_recipe = recipe
    end

    local previous_frame = (action_changed or action_restarted) and -1 or state.last_action_frame
    local trigger_frame = recipe and (recipe.whiff_trigger_frame or config.default_whiff_trigger_frame)
        or config.default_whiff_trigger_frame
    local late_frames = recipe and (recipe.whiff_max_late_frames or config.default_whiff_max_late_frames)
        or config.default_whiff_max_late_frames
    local crossed = eligible and previous_frame ~= nil
        and previous_frame < trigger_frame
        and current_frame >= trigger_frame
        and current_frame <= trigger_frame + late_frames
    state.last_action_frame = current_frame
    if crossed and state.last_whiff_action_serial ~= state.current_action_serial then
        state.last_whiff_action_serial = state.current_action_serial
        state.whiff_attempts = state.whiff_attempts + 1
        local dispatched = false
        if recipe.whiff_mode == "instance" then
            dispatched = dispatch_local_instance(recipe.whiff_effect_id, "whiff", recipe)
        else
            dispatched = dispatch_local(recipe.whiff_effect_id, "whiff", recipe)
        end
        if dispatched then
            state.whiff_successes = state.whiff_successes + 1
        end
    end
    persist()
end)

re.on_script_reset(function()
    release_active_instances("script-reset")
    state.active = false
    state.current_action_eligible = false
    state.current_action_frame = nil
    state.last_action_frame = nil
    state.last_eligible_action_tick = nil
    state.last_eligible_action_serial = nil
    state.last_eligible_recipe = nil
    state.current_recipe = nil
    state.status = "script reset; D-hardening hook retained but inert"
    state.dirty = true
    persist()
end)

return M
