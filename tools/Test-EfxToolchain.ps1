[CmdletBinding()]
param(
    [string]$EditorPath,
    [string]$TemplatePath,
    [string]$ColorScriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw '需要 PowerShell 7。' }

$candidates = @()
if ($EditorPath) { $candidates += $EditorPath }
$command = Get-Command '010editor' -ErrorAction SilentlyContinue
if ($command) { $candidates += $command.Source }
$candidates += @(
    (Join-Path $env:ProgramFiles '010 Editor\010Editor.exe'),
    (Join-Path ${env:ProgramFiles(x86)} '010 Editor\010Editor.exe')
)
$resolved = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $resolved) {
    Write-Error '未找到 010 Editor。请从 https://www.sweetscape.com/download/ 安装，并勾选加入 PATH。'
    exit 2
}
$repoRoot = Split-Path -Parent $PSScriptRoot
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config\efx-toolchain.lock.json') -Raw | ConvertFrom-Json
if (-not $TemplatePath) { $TemplatePath = Join-Path $repoRoot '.work\third-party\MHR-EFX-Template\RISE_EFX.bt' }
if (-not $ColorScriptPath) { $ColorScriptPath = Join-Path $repoRoot '.work\third-party\MHR-EFX-Template\EFX_COLOR_CHANGE.1sc' }
foreach ($item in @(
    @{ Path = $TemplatePath; Hash = $lock.template.templateSha256; Label = '模板' },
    @{ Path = $ColorScriptPath; Hash = $lock.template.colorScriptSha256; Label = '调色脚本' }
)) {
    if (-not (Test-Path -LiteralPath $item.Path)) { throw "缺少 EFX $($item.Label)：$($item.Path)" }
    $actual = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash
    if ($actual -ne $item.Hash) { throw "EFX $($item.Label)哈希与版本锁不一致。" }
}
Write-Output "LIHUO_010_EDITOR=OK"
Write-Output "EDITOR=$resolved"
Write-Output 'LIHUO_EFX_TEMPLATE=OK'
