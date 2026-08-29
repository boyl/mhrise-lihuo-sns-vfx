[CmdletBinding()]
param([string]$Version = '0.1.0-prototype')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$prototypeStage = Join-Path $repoRoot '.work\core-prototype-stage'
$sourceNatives = Join-Path $prototypeStage 'natives'
if (-not (Test-Path -LiteralPath $sourceNatives -PathType Container)) { throw '缺少 Core 原型暂存目录，请先运行 New-DiagnosticPrototypes.ps1。' }

$efxFiles = @(Get-ChildItem -LiteralPath $sourceNatives -Recurse -File -Filter '*.efx.2818730')
if ($efxFiles.Count -ne 10) { throw "安装器载荷必须包含 10 个 EFX，实际=$($efxFiles.Count)。" }
$stage = Join-Path $repoRoot '.work\prototype-installer'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'installer\INSTALL.cmd') -Destination $stage
Copy-Item -LiteralPath (Join-Path $repoRoot 'installer\UNINSTALL.cmd') -Destination $stage
Copy-Item -LiteralPath (Join-Path $repoRoot 'installer\install.ps1') -Destination $stage
Copy-Item -LiteralPath (Join-Path $repoRoot 'installer\uninstall.ps1') -Destination $stage
Copy-Item -LiteralPath $sourceNatives -Destination (Join-Path $stage 'payload\natives') -Recurse

$records = foreach ($file in $efxFiles) {
    $relative = [IO.Path]::GetRelativePath($prototypeStage, $file.FullName).Replace('\', '/')
    [ordered]@{ path = $relative; size = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
}
$payloadIdentity = ($records | Sort-Object path | ForEach-Object { $_.path + ':' + $_.sha256 }) -join "`n"
$payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payloadIdentity)))
[ordered]@{
    schemaVersion = 1
    candidate = "Lihuo-SnS-Core-$Version"
    payloadSha256 = $payloadSha
    files = @($records)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'payload-manifest.json') -Encoding utf8NoBOM

$readme = @(
    '离火片手 Core 原型开发候选。'
    '安装前完全退出游戏，运行 INSTALL.cmd；回退时运行 UNINSTALL.cmd。'
    '安装器只操作清单中的 10 个片手 EFX，并在复制后验证 SHA-256。'
) -join "`n"
$readme | Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Encoding utf8NoBOM
$dist = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zip = Join-Path $dist "Lihuo-SnS-Core-$Version-Installer.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Output 'LIHUO_INSTALLER_BUILD=OK'
Write-Output "STAGE=$stage"
Write-Output "PACKAGE=$zip"
