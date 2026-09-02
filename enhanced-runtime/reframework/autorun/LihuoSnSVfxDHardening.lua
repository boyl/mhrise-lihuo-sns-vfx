local ok, module_or_error = pcall(require, "LihuoSnSVfx.d_hardening_candidate")
if not ok then
    log.error("[LihuoSnSVfx:DHardening] loader failed: " .. tostring(module_or_error))
end

