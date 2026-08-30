local ok, error_message = pcall(require, "LihuoSnSVfx.effect_metadata_probe")

if not ok then
    log.error("[LihuoSnSVfx] metadata probe startup failed: " .. tostring(error_message))
end
