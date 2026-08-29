[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
