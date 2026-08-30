[CmdletBinding()]
param([string]$Version = '0.4.0-diagnostic')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $repoRoot '.work\action-probe-package'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
$autorun = Join-Path $stage 'reframework\autorun'
$target = Join-Path $autorun 'LihuoSnSVfx'
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'enhanced-runtime\reframework\autorun\LihuoSnSVfxRuntimeProbe.lua') -Destination $autorun
Copy-Item -LiteralPath (Join-Path $repoRoot 'enhanced-runtime\reframework\autorun\LihuoSnSVfx\runtime_probe.lua') -Destination $target
Copy-Item -LiteralPath (Join-Path $repoRoot 'enhanced-runtime\reframework\autorun\LihuoSnSVfxRequestProbe.lua') -Destination $autorun
Copy-Item -LiteralPath (Join-Path $repoRoot 'enhanced-runtime\reframework\autorun\LihuoSnSVfx\effect_request_probe.lua') -Destination $target
$readme = @(
    '离火片手攻击特效 Mod - 0.4.0 只读诊断包'
    ''
    '重要：当前包不会显示离火特效，也不会修改伤害、动作、存档或游戏资源。'
    '用途：记录片手动作、玩家特效组件和 ObjectEffectManager 请求，供正式效果实现使用。'
    ''
    '前置：REFramework。'
    '安装：将压缩包内 reframework 文件夹复制到 MonsterHunterRise.exe 所在目录并合并。'
    '输出：reframework/data/LihuoSnSVfx-runtime-probe.json'
    '输出：reframework/data/LihuoSnSVfx-effect-requests.json'
    '完整安装、卸载和故障排查见仓库 docs/installation.md。'
) -join "`n"
$readme | Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Encoding utf8NoBOM
Copy-Item -LiteralPath (Join-Path $repoRoot 'docs\installation.md') -Destination (Join-Path $stage 'INSTALLATION.md')
$dist = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zipPath = Join-Path $dist "Lihuo-SnS-Action-Probe-$Version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -CompressionLevel Optimal
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = @($archive.Entries | Where-Object { $_.FullName -and -not $_.FullName.EndsWith('/') })
    $paths = @($entries.FullName | ForEach-Object { $_.Replace('\', '/') })
    $expected = @(
        'README.txt',
        'INSTALLATION.md',
        'reframework/autorun/LihuoSnSVfxRuntimeProbe.lua',
        'reframework/autorun/LihuoSnSVfxRequestProbe.lua',
        'reframework/autorun/LihuoSnSVfx/runtime_probe.lua',
        'reframework/autorun/LihuoSnSVfx/effect_request_probe.lua'
    )
    if (@(Compare-Object $expected $paths).Count -gt 0) {
        throw "诊断包文件清单不一致：$($paths -join ', ')"
    }
    if (@($paths | Where-Object { $_ -match 'Dispatch|dispatch|\.dll$|\.exe$|\.efx\.' }).Count -gt 0) {
        throw '诊断包包含派发实验、第三方二进制或游戏资源。'
    }
}
finally { $archive.Dispose() }
Write-Output 'LIHUO_ACTION_PROBE_BUILD=OK'
Write-Output "PACKAGE=$zipPath"
