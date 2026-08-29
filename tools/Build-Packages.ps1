[CmdletBinding()]
param(
    [ValidateSet('Core', 'Enhanced')][string]$Variant = 'Core',
    [string]$Version = '0.1.0-prototype'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw '需要 PowerShell 7。' }

$repoRoot = Split-Path -Parent $PSScriptRoot
$assetRoot = Join-Path $repoRoot 'core-assets\natives'
$expected = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config\sns-efx.list') | Where-Object { $_ })
$actual = if (Test-Path -LiteralPath $assetRoot) { @(Get-ChildItem -LiteralPath $assetRoot -Recurse -File -Filter '*.efx.2818730') } else { @() }
if ($actual.Count -ne 10) { throw "构建要求 10 个已修改片手 EFX，实际=$($actual.Count)。核心视觉原型尚未完成时这是预期阻止。" }

$actualRelative = @($actual | ForEach-Object { [IO.Path]::GetRelativePath((Join-Path $repoRoot 'core-assets'), $_.FullName).Replace('/', '\') } | Sort-Object)
$expectedNormalized = @($expected | Sort-Object)
if (Compare-Object $expectedNormalized $actualRelative) { throw '核心资源路径与允许列表不一致。' }

$stage = Join-Path $repoRoot ".work\stage-$Variant"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -LiteralPath $assetRoot -Destination (Join-Path $stage 'natives') -Recurse
if ($Variant -eq 'Enhanced') {
    $runtime = Join-Path $repoRoot 'enhanced-runtime\reframework'
    if (-not (Test-Path -LiteralPath $runtime)) { throw '缺少增强运行时目录。' }
    Copy-Item -LiteralPath $runtime -Destination (Join-Path $stage 'reframework') -Recurse
}

$modInfo = @(
    "name=Lihuo SnS $Variant"
    "version=$Version"
    'description=Local-only Sword and Shield fire VFX for Monster Hunter Rise Sunbreak.'
    'author=boyl'
) -join "`n"
$modInfo | Set-Content -LiteralPath (Join-Path $stage 'modinfo.ini') -Encoding utf8NoBOM
$dist = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zip = Join-Path $dist "Lihuo-SnS-$Variant-$Version.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
& (Join-Path $PSScriptRoot 'Test-Package.ps1') -PackagePath $zip -Variant $Variant
Write-Output "LIHUO_BUILD=OK"
Write-Output "PACKAGE=$zip"
