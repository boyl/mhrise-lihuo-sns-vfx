#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GameRoot,
    [switch]$AllowRunningGameForIsolatedTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$StateName = '_lihuo_sns_vfx_d_hardening'
$PackageId = 'lihuo-sns-d-hardening'
$Policy = 'transactional_allowlisted_d_hardening_local_only'
$ExpectedFileCount = 87

function Resolve-Child([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|/|\\)\.\.($|/|\\)') {
        throw "不安全路径：$Relative"
    }
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $resolved = [IO.Path]::GetFullPath((Join-Path $resolvedRoot $Relative.Replace('/', '\')))
    if (-not $resolved.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "路径越界：$Relative"
    }
    $resolved
}

function Get-Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Json([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-AllowedPayloadPath([string]$Path) {
    if ($Path -cmatch '^natives/STM/vfx/(clip|decal|editor|mtu|provider)/[A-Za-z0-9_./-]+\.(clip\.43|pfb\.17|efx\.2818730|tex\.28)$') {
        return $true
    }
    return $Path -cin @(
        'reframework/autorun/LihuoSnSVfxDHardening.lua',
        'reframework/autorun/LihuoSnSVfx/d_hardening_candidate.lua',
        'reframework/data/LihuoSnSVfx-d-hardening.json'
    )
}

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam\steamapps\common\MonsterHunterRise'
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'MonsterHunterRise.exe') -PathType Leaf)) {
    throw '无效游戏根：找不到 MonsterHunterRise.exe。'
}
if (@(Get-Process -Name MonsterHunterRise -ErrorAction SilentlyContinue).Count -gt 0 -and
    -not ($AllowRunningGameForIsolatedTest -and
        (Test-Path -LiteralPath (Join-Path $GameRoot '.lihuo-isolated-test-root') -PathType Leaf))) {
    throw '游戏仍在运行，拒绝安装 D-hardening。'
}

foreach ($relative in @(
    'dinput8.dll',
    'reframework/plugins/FirstNatives.dll',
    'reframework/autorun/yunwulian/yun_modules.lua'
)) {
    if (-not (Test-Path -LiteralPath (Resolve-Child $GameRoot $relative) -PathType Leaf)) {
        throw "缺少 D-hardening 前置：$relative"
    }
}

$conflictIndicators = @(
    '_lihuo_sns_vfx_a_hit/current/install-state.json',
    '_lihuo_sns_vfx_core_candidate/install-state.json',
    '_lihuo_sns_vfx_intercept_poc/install-state.json',
    '_lihuo_sns_vfx_yun_visual/install-manifest.json',
    '_lihuo_sns_vfx_yun_dual_layer/install-manifest.json',
    '_lihuo_sns_vfx_yun_preflight/install-state.json',
    '_lihuo_sns_vfx_d_original_port/install-manifest.json',
    'reframework/autorun/ShortSwordVfx.lua',
    'reframework/autorun/LihuoSnSVfxYunDispatch.lua',
    'reframework/autorun/LihuoSnSVfxYunDualLayer.lua',
    'reframework/autorun/LihuoSnSVfxIndependentPoc.lua'
)
foreach ($relative in $conflictIndicators) {
    if (Test-Path -LiteralPath (Resolve-Child $GameRoot $relative)) {
        throw "检测到其他候选或原 D 入口，拒绝混装：$relative"
    }
}
$bStatePath = Resolve-Child $GameRoot 'reframework/data/LihuoSnSVfx-independent-dual-layer-install-state.json'
if (Test-Path -LiteralPath $bStatePath -PathType Leaf) {
    $bState = Read-Json $bStatePath
    if ([string]$bState.phase -eq 'installed') { throw '检测到活动 B 候选，拒绝混装 D-hardening。' }
}

$manifestPath = Join-Path $PSScriptRoot 'payload-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw '缺少 payload-manifest.json。' }
$manifest = Read-Json $manifestPath
$files = @($manifest.files)
if ($manifest.schema_version -ne 1 -or $manifest.policy -ne $Policy -or
    $manifest.package_id -ne $PackageId -or $manifest.package_ready -ne $true -or
    $manifest.real_game_install_permitted -ne $true -or $files.Count -ne $ExpectedFileCount) {
    throw 'D-hardening 清单身份、策略、就绪状态或文件数量无效。'
}
$seen = @{}
$sources = @()
foreach ($record in $files) {
    $relative = [string]$record.path
    if (-not (Test-AllowedPayloadPath $relative)) { throw "载荷路径不在精确允许列表：$relative" }
    $key = $relative.ToLowerInvariant()
    if ($seen.ContainsKey($key)) { throw "载荷路径大小写冲突：$relative" }
    $seen[$key] = $true
    $source = Resolve-Child $PSScriptRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
        (Get-Sha $source) -ne [string]$record.sha256 -or
        (Get-Item -LiteralPath $source).Length -ne [long]$record.size) {
        throw "载荷哈希或大小不匹配：$relative"
    }
    $sources += [pscustomobject]@{ relative = $relative; source = $source; hash = [string]$record.sha256 }
}

$configPath = Resolve-Child $PSScriptRoot 'reframework/data/LihuoSnSVfx-d-hardening.json'
$config = Read-Json $configPath
if ($config.schema_version -ne 2 -or $config.enabled -ne $true -or $config.network_sync -ne $false -or
    [int]$config.weapon_type -ne 8 -or [int]$config.action_bank -ne 100 -or
    [int]$config.container_id -ne 150 -or @($config.recipes).Count -lt 20 -or
    @($config.recipes | Where-Object { [int]$_.action_id -eq 108 -and
        [int]$_.whiff_effect_id -eq 24007 -and [int]$_.hit_effect_id -eq 30007 }).Count -ne 1) {
    throw 'D-hardening 配置不满足本地全动作配方与 Motion108 基准硬边界。'
}

$stateRoot = Join-Path $GameRoot $StateName
$installedManifestPath = Join-Path $stateRoot 'install-manifest.json'
if (Test-Path -LiteralPath $stateRoot) {
    if (-not (Test-Path -LiteralPath $installedManifestPath -PathType Leaf)) {
        throw 'D-hardening 状态目录不完整，拒绝覆盖。'
    }
    $existing = Read-Json $installedManifestPath
    if ([string]$existing.package_sha256 -ne [string]$manifest.package_sha256) {
        throw 'D-hardening 已安装状态来自不同包。'
    }
    foreach ($record in @($existing.files)) {
        $target = Resolve-Child $GameRoot ([string]$record.path)
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
            (Get-Sha $target) -ne [string]$record.installed_sha256) {
            throw "D-hardening 已安装目标漂移：$($record.path)"
        }
    }
    'LIHUO_D_HARDENING_INSTALL=ALREADY_INSTALLED'
    return
}

$transaction = "$stateRoot.staging-$([guid]::NewGuid().ToString('N'))"
$backupRoot = Join-Path $transaction 'backup'
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
$records = @()
$written = @()
try {
    foreach ($sourceRecord in $sources) {
        $target = Resolve-Child $GameRoot $sourceRecord.relative
        $preexisting = Test-Path -LiteralPath $target -PathType Leaf
        if (-not $preexisting -and (Test-Path -LiteralPath $target)) {
            throw "目标存在但不是文件：$($sourceRecord.relative)"
        }
        $originalSha = if ($preexisting) { Get-Sha $target } else { $null }
        $backupRelative = if ($preexisting) { 'backup/' + $sourceRecord.relative } else { $null }
        if ($preexisting) {
            $backup = Resolve-Child $transaction $backupRelative
            [IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
            Copy-Item -LiteralPath $target -Destination $backup
            if ((Get-Sha $backup) -ne $originalSha) { throw "备份校验失败：$($sourceRecord.relative)" }
        }
        $records += [ordered]@{
            path = $sourceRecord.relative
            source_sha256 = $sourceRecord.hash
            installed_sha256 = $sourceRecord.hash
            preexisting = [bool]$preexisting
            original_sha256 = $originalSha
            backup_path = $backupRelative
        }
    }
    foreach ($record in $records) {
        $source = Resolve-Child $PSScriptRoot ([string]$record.path)
        $target = Resolve-Child $GameRoot ([string]$record.path)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
        $written += $record
        if ((Get-Sha $target) -ne [string]$record.installed_sha256) {
            throw "写入校验失败：$($record.path)"
        }
    }
    [ordered]@{
        schema_version = 1
        policy = $Policy
        status = 'installed'
        package_id = $PackageId
        package_version = [string]$manifest.package_version
        package_sha256 = [string]$manifest.package_sha256
        source_archive_sha256 = [string]$manifest.source_archive_sha256
        installed_at_utc = [DateTime]::UtcNow.ToString('o')
        game_root = $GameRoot
        files = $records
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $transaction 'install-manifest.json') -Encoding utf8NoBOM
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination (Join-Path $transaction 'Rollback.ps1')
    Move-Item -LiteralPath $transaction -Destination $stateRoot
}
catch {
    for ($index = $written.Count - 1; $index -ge 0; $index--) {
        $record = $written[$index]
        $target = Resolve-Child $GameRoot ([string]$record.path)
        if ([bool]$record.preexisting) {
            $backup = Resolve-Child $transaction ([string]$record.backup_path)
            if (Test-Path -LiteralPath $backup -PathType Leaf) {
                Copy-Item -LiteralPath $backup -Destination $target -Force
            }
        }
        elseif (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
        }
    }
    if (Test-Path -LiteralPath $transaction) { Remove-Item -LiteralPath $transaction -Recurse -Force }
    throw
}

"MANIFEST=$installedManifestPath"
'LIHUO_D_HARDENING_INSTALL=OK'
