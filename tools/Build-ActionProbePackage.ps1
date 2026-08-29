[CmdletBinding()]
param([string]$Version = '0.1.0-probe')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $repoRoot '.work\action-probe-package'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
$target = Join-Path $stage 'reframework\autorun\LihuoSnSVfx'
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'enhanced-runtime\reframework\autorun\LihuoSnSVfx\action_probe.lua') -Destination $target
$readme = @(
    'Lihuo SnS read-only action mapping probe.'
    'Requires REFramework. This development package does not spawn effects or alter combat.'
    'Output: reframework/data/LihuoSnSVfx-action-probe.json'
) -join "`n"
$readme | Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Encoding utf8NoBOM
$dist = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zipPath = Join-Path $dist "Lihuo-SnS-Action-Probe-$Version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -CompressionLevel Optimal
Write-Output 'LIHUO_ACTION_PROBE_BUILD=OK'
Write-Output "PACKAGE=$zipPath"
