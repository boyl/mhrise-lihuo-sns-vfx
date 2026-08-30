local ok, error_message = pcall(require, "LihuoSnSVfx.runtime_probe")

if not ok then
    log.error("[LihuoSnSVfx] runtime probe startup failed: " .. tostring(error_message))
end
