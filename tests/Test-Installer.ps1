[CmdletBinding()]
param([string]$InstallerRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) '.work\prototype-installer'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path $env:TEMP ("lihuo-installer-contract-$PID")
$resolvedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$resolvedTest = [IO.Path]::GetFullPath($testRoot)
if (-not $resolvedTest.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) { throw '临时测试目录越界。' }

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $testRoot 'MonsterHunterRise.exe') -Value 'installer contract fixture' -Encoding ascii
    & (Join-Path $InstallerRoot 'install.ps1') -GameRoot $testRoot -NonInteractive
    if (@(Get-ChildItem -LiteralPath (Join-Path $testRoot 'natives') -Recurse -File -Filter '*.efx.2818730').Count -ne 10) {
        throw '安装器未安装恰好 10 个 EFX。'
    }
    & (Join-Path $InstallerRoot 'install.ps1') -GameRoot $testRoot -NonInteractive
    & (Join-Path $InstallerRoot 'uninstall.ps1') -GameRoot $testRoot -NonInteractive
    if (@(Get-ChildItem -LiteralPath (Join-Path $testRoot 'natives') -Recurse -File -ErrorAction SilentlyContinue).Count -ne 0) {
        throw '卸载后仍残留候选文件。'
    }
    if (Test-Path -LiteralPath (Join-Path $testRoot '_lihuo_sns_vfx')) { throw '卸载后仍残留安装状态。' }
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Output 'LIHUO_INSTALLER_CONTRACT=OK'
