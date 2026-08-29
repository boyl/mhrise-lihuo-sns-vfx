[CmdletBinding()]
param(
    [string]$GameRoot = (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\MonsterHunterRise'),
    [string]$REToolPath,
    [string]$HashListPath,
    [string]$WorkRoot,
    [switch]$AllowUnknownExecutable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw '需要 PowerShell 7。' }

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $HashListPath) { $HashListPath = Join-Path $PSScriptRoot 'config\sns-efx.list' }
if (-not $WorkRoot) { $WorkRoot = Join-Path $repoRoot '.work' }
$expectedVersion = '16.0.2.0'
$expectedExeHash = '29FA23A9CE24613A9B05CE84F7EBFA3262AAF5053B377B43FD8DFC09071AA7FC'

if (-not $REToolPath) {
    if ($env:RETOOL_PATH) { $REToolPath = $env:RETOOL_PATH }
    else {
        $retoolCommand = Get-Command 'REtool' -ErrorAction SilentlyContinue
        if ($retoolCommand) { $REToolPath = $retoolCommand.Source }
    }
}
if (-not $REToolPath) { throw '未找到 RETool。请使用 -REToolPath 或 RETOOL_PATH 指定。' }

foreach ($required in @($GameRoot, $REToolPath, $HashListPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "路径不存在：$required" }
}
$gameExe = Join-Path $GameRoot 'MonsterHunterRise.exe'
if (-not (Test-Path -LiteralPath $gameExe)) { throw "找不到游戏程序：$gameExe" }
$version = (Get-Item -LiteralPath $gameExe).VersionInfo.FileVersion
$exeHash = (Get-FileHash -LiteralPath $gameExe -Algorithm SHA256).Hash
if (-not $AllowUnknownExecutable -and ($version -ne $expectedVersion -or $exeHash -ne $expectedExeHash)) {
    throw "游戏版本或哈希不匹配。实际版本=$version，SHA256=$exeHash"
}

$paths = @(Get-Content -LiteralPath $HashListPath | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$uniquePaths = @($paths | Sort-Object -Unique)
if ($paths.Count -ne 10 -or $uniquePaths.Count -ne 10) { throw "片手 EFX 清单必须恰好包含 10 个唯一条目，实际=$($paths.Count)/$($uniquePaths.Count)。" }
foreach ($path in $paths) {
    if ($path -notmatch '^natives\\STM\\vfx\\editor\\efd_pl\\efd_s-swd\\[^\\]+\.efx\.2818730$') {
        throw "清单包含越界路径：$path"
    }
}

$originalRoot = Join-Path $WorkRoot 'original'
New-Item -ItemType Directory -Path $originalRoot -Force | Out-Null
$paks = @(Get-ChildItem -LiteralPath $GameRoot -File -Filter 're_chunk_000*.pak' |
    Sort-Object @{ Expression = { if ($_.Name -eq 're_chunk_000.pak') { 0 } else { 1 } } }, Name)
if ($paks.Count -eq 0) { throw '未找到 re_chunk_000*.pak。' }

Push-Location $originalRoot
try {
    foreach ($pak in $paks) {
        & $REToolPath -h $HashListPath -x $pak.FullName -skipUnknowns -noExtractDir
        # RETool v0.240 在成功提取且跳过未知条目时也可能返回 1；
        # 最终以允许列表的 10 个文件是否完整存在作为决定性门禁。
        if ($LASTEXITCODE -notin @(0, 1)) { throw "RETool 提取失败：$($pak.FullName)，退出码=$LASTEXITCODE" }
    }
}
finally { Pop-Location }

$records = foreach ($relative in $paths) {
    $full = Join-Path $originalRoot $relative
    if (-not (Test-Path -LiteralPath $full)) { throw "提取后缺少：$relative" }
    $item = Get-Item -LiteralPath $full
    [ordered]@{ path = $relative.Replace('\', '/'); size = $item.Length; sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash }
}
$manifest = [ordered]@{
    schemaVersion = 1
    gameVersion = $version
    gameExecutableSha256 = $exeHash
    sourcePaks = @($paks.Name)
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    files = @($records)
}
$manifestPath = Join-Path $WorkRoot 'original-manifest.json'
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
Write-Output "LIHUO_EXTRACTION=OK"
Write-Output "MANIFEST=$manifestPath"
