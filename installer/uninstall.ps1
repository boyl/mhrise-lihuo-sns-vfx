#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GameRoot = (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\MonsterHunterRise'),
    [switch]$NonInteractive,
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $GameRoot '_lihuo_sns_vfx'
$statePath = Join-Path $stateRoot 'install-state.json'
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
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw '没有找到由本候选安装器生成的安装状态，拒绝猜测删除目标。' }
if (-not (Test-TargetWritable -Path $GameRoot)) {
    if ($Elevated) { throw "即使提权后仍无法写入：$GameRoot" }
    $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -GameRoot "{1}" -Elevated' -f $PSCommandPath, $GameRoot
    if ($NonInteractive) { $arguments += ' -NonInteractive' }
    Start-Process -FilePath $pwsh -Verb RunAs -WindowStyle Normal -ArgumentList $arguments
    exit 0
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
foreach ($file in $state.files) {
    $target = Join-Path $GameRoot $file.path.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "待卸载文件已缺失：$($file.path)" }
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($hash -ne $file.installedSha256) { throw "待卸载文件已被其他 Mod 修改，拒绝删除：$($file.path)" }
}

foreach ($file in $state.files) {
    $target = Join-Path $GameRoot $file.path.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ($file.hadExisting -and $file.backup) {
        $backup = Join-Path $stateRoot $file.backup.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "缺少原文件备份：$($file.path)" }
        Copy-Item -LiteralPath $backup -Destination $target -Force
    }
    else {
        Remove-Item -LiteralPath $target -Force
    }
}

Remove-Item -LiteralPath $stateRoot -Recurse -Force
Write-Host '离火片手 Core 原型已卸载；候选文件已删除，安装前存在的文件已恢复。' -ForegroundColor Green
if (-not $NonInteractive) { Read-Host '按 Enter 关闭' | Out-Null }
