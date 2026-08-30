[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeProbeLoader = Join-Path $repoRoot 'enhanced-runtime/reframework/autorun/LihuoSnSVfxRuntimeProbe.lua'
$runtimeProbeModule = Join-Path $repoRoot 'enhanced-runtime/reframework/autorun/LihuoSnSVfx/runtime_probe.lua'

if (-not (Test-Path -LiteralPath $runtimeProbeLoader -PathType Leaf)) {
    throw '缺少 REFramework autorun 根入口：LihuoSnSVfxRuntimeProbe.lua'
}
if (-not (Test-Path -LiteralPath $runtimeProbeModule -PathType Leaf)) {
    throw '缺少运行时探针模块：runtime_probe.lua'
}
$loaderText = Get-Content -LiteralPath $runtimeProbeLoader -Raw
if ($loaderText -notmatch 'pcall\(require,\s*"LihuoSnSVfx\.runtime_probe"\)') {
    throw '运行时探针根入口未加载正确模块。'
}
$runtimeProbeText = Get-Content -LiteralPath $runtimeProbeModule -Raw
if ($runtimeProbeText -notmatch 'SWORD_AND_SHIELD_WEAPON_TYPE\s*=\s*8' -or
    $runtimeProbeText -notmatch 'snow\.player\.ShortSword') {
    throw '片手运行时身份必须同时使用实机枚举 8 与 snow.player.ShortSword。'
}
$dispatchProbe = Join-Path $repoRoot 'enhanced-runtime/reframework/autorun/LihuoSnSVfx/effect_dispatch_probe.lua'
$dispatchLoader = Join-Path $repoRoot 'enhanced-runtime/reframework/autorun/LihuoSnSVfxDispatchProbe.lua'
if (-not (Test-Path -LiteralPath $dispatchProbe -PathType Leaf) -or
    -not (Test-Path -LiteralPath $dispatchLoader -PathType Leaf)) {
    throw '缺少单次特效派发探针及其 autorun 根入口。'
}
$dispatchText = Get-Content -LiteralPath $dispatchProbe -Raw
if ($dispatchText -notmatch 'single_bounded_visible_effect_dispatch' -or
    $dispatchText -notmatch 'state\.attempted\s*=\s*true') {
    throw '特效派发探针必须保留单次有界执行门禁。'
}
if ($dispatchText -notmatch 'resource:create_holder\("via\.effect\.EffectResourceHolder"\)' -or
    $dispatchText -notmatch 'value:add_ref\(\)') {
    throw '特效资源必须使用 REFramework 的 REResource 持有器与显式引用契约。'
}
$requestProbe = Join-Path $repoRoot 'enhanced-runtime/reframework/autorun/LihuoSnSVfx/effect_request_probe.lua'
$requestLoader = Join-Path $repoRoot 'enhanced-runtime/reframework/autorun/LihuoSnSVfxRequestProbe.lua'
if (-not (Test-Path -LiteralPath $requestProbe -PathType Leaf) -or
    -not (Test-Path -LiteralPath $requestLoader -PathType Leaf)) {
    throw '缺少 ObjectEffectManager 请求记录器及其 autorun 根入口。'
}
$requestText = Get-Content -LiteralPath $requestProbe -Raw
foreach ($required in @(
    'read_only_player_object_effect_request_hook',
    'requestEffectFromFsm(System.UInt32, System.UInt32, System.Int32)',
    'requestEffectFromFsm(System.UInt32, System.Int32)',
    'requestEffectFromFsmOrSequence(System.UInt32, System.UInt32, System.Int32)',
    'address ~= state.target_manager_address'
)) {
    if (-not $requestText.Contains($required)) { throw "特效请求记录器缺少契约：$required" }
}
foreach ($forbidden in @('sdk.call_native_func', 'createEffectAutoDestroy', 'setResources')) {
    if ($requestText -match [regex]::Escape($forbidden)) {
        throw "只读特效请求记录器包含禁止能力：$forbidden"
    }
}
if ($PSVersionTable.PSVersion.Major -lt 7) { throw '需要 PowerShell 7。' }
$repoRoot = Split-Path -Parent $PSScriptRoot

$expectedPaths = @(Get-Content -LiteralPath (Join-Path $repoRoot 'tools\config\sns-efx.list') | Where-Object { $_ })
if ($expectedPaths.Count -ne 10 -or @($expectedPaths | Sort-Object -Unique).Count -ne 10) { throw '片手 EFX 清单契约失败。' }
if (@($expectedPaths | Where-Object { $_ -notmatch 'efd_s-swd' }).Count -gt 0) { throw '片手 EFX 清单越界。' }

$recipe = Get-Content -LiteralPath (Join-Path $repoRoot 'core-assets\recipes\visual-tiers.json') -Raw | ConvertFrom-Json
if (@($recipe.tiers.PSObject.Properties.Name) -join ',' -ne 'normal,finisher,signature') { throw '三级视觉配方契约失败。' }
if ($recipe.globalLimits.persistentLoopingParticlesAllowed -ne $false) { throw '禁止持续残留粒子的契约失败。' }

$toolchainLock = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\config\efx-toolchain.lock.json') -Raw | ConvertFrom-Json
if ($toolchainLock.template.redistribute -ne $false -or $toolchainLock.editor.redistribute -ne $false) { throw '第三方工具再分发边界失败。' }
if ($toolchainLock.template.commit.Length -ne 40) { throw 'EFX 模板版本锁失败。' }

$probePath = Join-Path $repoRoot 'enhanced-runtime\reframework\autorun\LihuoSnSVfx\action_probe.lua'
$probe = Get-Content -LiteralPath $probePath -Raw
foreach ($required in @('findMasterPlayer', '_playerWeaponType', 'getMotionFsm2', 'read_only_sword_and_shield_action_transitions')) {
    if (-not $probe.Contains($required)) { throw "动作探针缺少契约：$required" }
}
foreach ($forbidden in @('sdk.hook', 'spawn', 'createEffect', 'RemoveCollectibleEffect')) {
    if ($probe -match [regex]::Escape($forbidden)) { throw "只读动作探针包含禁止能力：$forbidden" }
}

$trackedBinaries = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Extension -match '^\.(dll|exe|pak)$'
})
if ($trackedBinaries.Count -gt 0) { throw "仓库包含禁止二进制：$($trackedBinaries.FullName -join ', ')" }

$trackedText = Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]\.work[\\/]' -and $_.FullName -notmatch '[\\/]dist[\\/]'
}
foreach ($file in $trackedText) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match 'C:\\Users\\lw') { throw "源码包含个人绝对路径：$($file.FullName)" }
}

$prototype = Join-Path $repoRoot 'dist\Lihuo-SnS-Core-0.1.0-prototype.zip'
if (Test-Path -LiteralPath $prototype) {
    & (Join-Path $repoRoot 'tools\Test-Package.ps1') -PackagePath $prototype -Variant Core
    $diagnosticManifestPath = Join-Path $repoRoot 'dist\diagnostics\diagnostic-manifest.json'
    $diagnosticManifest = Get-Content -LiteralPath $diagnosticManifestPath -Raw | ConvertFrom-Json
    if (@($diagnosticManifest.packages).Count -ne 10) { throw '诊断包数量契约失败。' }
    if (@($diagnosticManifest.packages | Where-Object { $_.sourceSha256 -eq $_.diagnosticSha256 }).Count -gt 0) {
        throw '诊断 EFX 未产生差异。'
    }
}

Write-Output 'LIHUO_TESTS=OK'
