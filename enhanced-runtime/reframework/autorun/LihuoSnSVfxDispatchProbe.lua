local ok, error_message = pcall(require, "LihuoSnSVfx.effect_dispatch_probe")

if not ok then
    log.error("[LihuoSnSVfx] dispatch probe startup failed: " .. tostring(error_message))
end
