local ok, result = pcall(require, "LihuoSnSVfx.effect_request_probe")
if not ok then
    log.error("[Lihuo SnS VFX] effect request probe failed to load: " .. tostring(result))
end
