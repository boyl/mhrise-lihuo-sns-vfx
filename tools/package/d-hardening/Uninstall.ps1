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

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    if ((Split-Path -Leaf $PSScriptRoot) -eq $StateName) {
        $GameRoot = Split-Path -Parent $PSScriptRoot
    }
    else {
        $GameRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam\steamapps\common\MonsterHunterRise'
    }
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'MonsterHunterRise.exe') -PathType Leaf)) {
    throw '无效游戏根。'
}
if (@(Get-Process -Name MonsterHunterRise -ErrorAction SilentlyContinue).Count -gt 0 -and
    -not ($AllowRunningGameForIsolatedTest -and
        (Test-Path -LiteralPath (Join-Path $GameRoot '.lihuo-isolated-test-root') -PathType Leaf))) {
    throw '游戏仍在运行，拒绝回滚 D-hardening。'
}

$stateRoot = Join-Path $GameRoot $StateName
$manifestPath = Join-Path $stateRoot 'install-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw '找不到 D-hardening 安装 manifest。' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema_version -ne 1 -or $manifest.policy -ne $Policy -or
    $manifest.package_id -ne $PackageId -or $manifest.status -ne 'installed' -or
    @($manifest.files).Count -ne $ExpectedFileCount -or
    [IO.Path]::GetFullPath([string]$manifest.game_root).TrimEnd('\') -ne $GameRoot) {
    throw 'D-hardening manifest 身份、数量或游戏根不匹配。'
}

# 回滚前先完整验证所有目标与备份，任一漂移都不进行写入。
foreach ($record in @($manifest.files)) {
    $target = Resolve-Child $GameRoot ([string]$record.path)
    if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
        (Get-Sha $target) -ne [string]$record.installed_sha256) {
        throw "目标缺失或漂移，拒绝部分回滚：$($record.path)"
    }
    if ([bool]$record.preexisting) {
        $backup = Resolve-Child $stateRoot ([string]$record.backup_path)
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or
            (Get-Sha $backup) -ne [string]$record.original_sha256) {
            throw "备份缺失或漂移：$($record.path)"
        }
    }
}

foreach ($record in @($manifest.files)) {
    $target = Resolve-Child $GameRoot ([string]$record.path)
    if ([bool]$record.preexisting) {
        $backup = Resolve-Child $stateRoot ([string]$record.backup_path)
        Copy-Item -LiteralPath $backup -Destination $target -Force
        if ((Get-Sha $target) -ne [string]$record.original_sha256) {
            throw "恢复校验失败：$($record.path)"
        }
    }
    else {
        Remove-Item -LiteralPath $target -Force
        if (Test-Path -LiteralPath $target) { throw "删除失败：$($record.path)" }
    }
}
Remove-Item -LiteralPath $stateRoot -Recurse -Force
'LIHUO_D_HARDENING_ROLLBACK=OK'
