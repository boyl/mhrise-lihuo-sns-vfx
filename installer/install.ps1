#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GameRoot = (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\MonsterHunterRise'),
    [switch]$NonInteractive,
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path $PSScriptRoot 'payload'
$manifestPath = Join-Path $PSScriptRoot 'payload-manifest.json'
$stateRoot = Join-Path $GameRoot '_lihuo_sns_vfx'
$statePath = Join-Path $stateRoot 'install-state.json'
$expectedPrefix = 'natives/STM/vfx/editor/efd_pl/efd_s-swd/'

function Test-TargetWritable {
    param([string]$Path)
    $probe = Join-Path $Path ('.lihuo-write-test-' + $PID + '.tmp')
    try {
        [IO.File]::WriteAllText($probe, 'test')
        Remove-Item -LiteralPath $probe -Force
        return $true
    }
    catch { return $false }
}

if (Get-Process -Name MonsterHunterRise -ErrorAction SilentlyContinue) { throw '请先完全退出 Monster Hunter Rise。' }
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'MonsterHunterRise.exe') -PathType Leaf)) { throw "游戏目录无效：$GameRoot" }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw '缺少 payload-manifest.json。' }
if (-not (Test-TargetWritable -Path $GameRoot)) {
    if ($Elevated) { throw "即使提权后仍无法写入：$GameRoot" }
    $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -GameRoot "{1}" -Elevated' -f $PSCommandPath, $GameRoot
    if ($NonInteractive) { $arguments += ' -NonInteractive' }
    Start-Process -FilePath $pwsh -Verb RunAs -WindowStyle Normal -ArgumentList $arguments
    exit 0
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$files = @($manifest.files)
if ($files.Count -ne 10) { throw "安装清单必须恰好包含 10 个文件，实际=$($files.Count)。" }
if (@($files.path | Sort-Object -Unique).Count -ne 10) { throw '安装清单存在重复路径。' }
foreach ($file in $files) {
    if (-not $file.path.StartsWith($expectedPrefix, [StringComparison]::Ordinal) -or $file.path -notmatch '\.efx\.2818730$') {
        throw "安装清单越界：$($file.path)"
    }
}

if (Test-Path -LiteralPath $statePath) {
    $oldState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $allMatch = $true
    foreach ($file in $oldState.files) {
        $target = Join-Path $GameRoot $file.path.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $file.installedSha256) {
            $allMatch = $false
            break
        }
    }
    if ($allMatch -and $oldState.payloadSha256 -eq $manifest.payloadSha256) {
        Write-Host '离火片手 Core 原型已经安装且哈希一致。' -ForegroundColor Green
        exit 0
    }
    throw '检测到既有离火安装状态与当前文件不一致；请先运行对应版本的卸载器。'
}

$pendingRoot = Join-Path $stateRoot 'pending'
$backupRoot = Join-Path $pendingRoot 'backup'
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$installed = @()
try {
    foreach ($file in $files) {
        $relative = $file.path.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $source = Join-Path $sourceRoot $relative
        $target = Join-Path $GameRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "候选包缺少：$($file.path)" }
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if ($sourceHash -ne $file.sha256) { throw "候选文件哈希不匹配：$($file.path)" }

        $hadExisting = Test-Path -LiteralPath $target -PathType Leaf
        $backupRelative = $null
        if ($hadExisting) {
            $backup = Join-Path $backupRoot $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $backup
            $backupRelative = ('backup/' + $relative.Replace('\', '/'))
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
        $targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($targetHash -ne $sourceHash) { throw "安装后哈希不匹配：$($file.path)" }
        $installed += [ordered]@{
            path = $file.path
            installedSha256 = $targetHash
            hadExisting = $hadExisting
            backup = $backupRelative
        }
    }

    $state = [ordered]@{
        schemaVersion = 1
        candidate = $manifest.candidate
        payloadSha256 = $manifest.payloadSha256
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        files = $installed
    }
    $finalBackup = Join-Path $stateRoot 'backup'
    if (Test-Path -LiteralPath $backupRoot) { Move-Item -LiteralPath $backupRoot -Destination $finalBackup }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
    if (Test-Path -LiteralPath $pendingRoot) { Remove-Item -LiteralPath $pendingRoot -Recurse -Force }
}
catch {
    foreach ($item in @($installed)) {
        $target = Join-Path $GameRoot $item.path.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if ($item.hadExisting -and $item.backup) {
            $relative = $item.path.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $backup = Join-Path $backupRoot $relative
            if (-not (Test-Path -LiteralPath $backup)) { $backup = Join-Path $stateRoot $item.backup.Replace('/', [IO.Path]::DirectorySeparatorChar) }
            if (Test-Path -LiteralPath $backup) { Copy-Item -LiteralPath $backup -Destination $target -Force }
        }
        elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
    }
    if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
    throw
}

Write-Host '离火片手 Core 原型安装完成，10/10 文件哈希验证通过。' -ForegroundColor Green
if (-not $NonInteractive) { Read-Host '按 Enter 关闭' | Out-Null }
