[CmdletBinding()]
param(
    [string]$EditorPath,
    [string]$TemplatePath,
    [string]$ColorScriptPath,
    [string]$PrimaryColor = '240,40,40,999',
    [string]$SecondaryColor = '255,190,40,999',
    [int]$TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw '需要 PowerShell 7。' }
if ($PrimaryColor -notmatch '^\d{1,3},\d{1,3},\d{1,3},(?:\d{1,3}|999)$' -or
    $SecondaryColor -notmatch '^\d{1,3},\d{1,3},\d{1,3},(?:\d{1,3}|999)$') {
    throw '颜色格式必须为 R,G,B,A；A=999 表示保留原透明度。'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$workRoot = Join-Path $repoRoot '.work'
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config\efx-toolchain.lock.json') -Raw | ConvertFrom-Json
if (-not $EditorPath) {
    $command = Get-Command '010editor' -ErrorAction SilentlyContinue
    if ($command) { $EditorPath = $command.Source }
    else { $EditorPath = Join-Path $env:ProgramFiles '010 Editor\010Editor.exe' }
}
if (-not $TemplatePath) { $TemplatePath = Join-Path $workRoot 'third-party\MHR-EFX-Template\RISE_EFX.bt' }
if (-not $ColorScriptPath) { $ColorScriptPath = Join-Path $workRoot 'third-party\MHR-EFX-Template\EFX_COLOR_CHANGE.1sc' }
foreach ($required in @($EditorPath, $TemplatePath, $ColorScriptPath, (Join-Path $workRoot 'original-manifest.json'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "缺少诊断原型输入：$required" }
}
if ((Get-FileHash -LiteralPath $TemplatePath -Algorithm SHA256).Hash -ne $lock.template.templateSha256) { throw 'EFX 模板哈希与版本锁不一致。' }
if ((Get-FileHash -LiteralPath $ColorScriptPath -Algorithm SHA256).Hash -ne $lock.template.colorScriptSha256) { throw '调色脚本哈希与版本锁不一致。' }

# 第三方脚本没有明确再分发许可：仅在忽略目录中生成本机批处理副本，不写入源码或分发包。
$batchScript = Join-Path $workRoot 'generated\diagnostic-color.1sc'
New-Item -ItemType Directory -Path (Split-Path -Parent $batchScript) -Force | Out-Null
$script = Get-Content -LiteralPath $ColorScriptPath -Raw
$script = [regex]::Replace($script, 'local string\s+DEFAULT_COLOR\s*=\s*"[^"]+";', "local string    DEFAULT_COLOR = `"$PrimaryColor`";", 1)
$script = [regex]::Replace($script, 'local string\s+DEFAULT_SECONDARY_COLOR\s*=\s*"[^"]+";', "local string    DEFAULT_SECONDARY_COLOR = `"$SecondaryColor`";", 1)
$script = [regex]::Replace($script, 'local string COLORSTRING = InputString\([\s\S]*?,DEFAULT_COLOR\);', 'local string COLORSTRING = DEFAULT_COLOR;', 1)
$script = [regex]::Replace($script, 'local string COLORSTRING2 = InputString\([\s\S]*?,DEFAULT_SECONDARY_COLOR\);', 'local string COLORSTRING2 = DEFAULT_SECONDARY_COLOR;', 1)
if ($script.Contains('InputString(')) { throw '无法将第三方调色脚本转换为无交互批处理。' }
$script += @'

if (FileSave() < 0)
{
    Exit(-10);
}
Terminate(TRUE);
'@
$script | Set-Content -LiteralPath $batchScript -Encoding utf8NoBOM

$manifest = Get-Content -LiteralPath (Join-Path $workRoot 'original-manifest.json') -Raw | ConvertFrom-Json
$diagnosticRoot = Join-Path $workRoot 'diagnostics'
$outputRoot = Join-Path $repoRoot 'dist\diagnostics'
New-Item -ItemType Directory -Path $diagnosticRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$prototypeStage = Join-Path $workRoot 'core-prototype-stage'
if (Test-Path -LiteralPath $prototypeStage) { Remove-Item -LiteralPath $prototypeStage -Recurse -Force }
New-Item -ItemType Directory -Path $prototypeStage -Force | Out-Null
$results = @()
foreach ($record in $manifest.files) {
    $relative = $record.path.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $source = Join-Path (Join-Path $workRoot 'original') $relative
    $id = [IO.Path]::GetFileName($relative).Replace('.efx.2818730', '')
    $stage = Join-Path $diagnosticRoot $id
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    $target = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Resolve-Path -LiteralPath $EditorPath).Path
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    foreach ($argument in @(
        '-noui', '-nowarnings', (Resolve-Path -LiteralPath $target).Path,
        ('-template:' + (Resolve-Path -LiteralPath $TemplatePath).Path),
        ('-script:' + (Resolve-Path -LiteralPath $batchScript).Path)
    )) { [void]$startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($startInfo)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        throw "010 Editor 处理超时：$id。请先完成首次启动许可确认。"
    }
    if ($process.ExitCode -ne 0) { throw "010 Editor 处理失败：$id，退出码=$($process.ExitCode)。" }

    $newHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($newHash -eq $record.sha256) { throw "诊断色未改变文件：$id" }
    if ((Get-Item -LiteralPath $target).Length -ne [long]$record.size) { throw "调色不应改变 EFX 文件大小：$id" }

    $modInfo = @(
        "name=Lihuo SnS Diagnostic $id"
        'version=0.1.0-diagnostic'
        "description=Enable only this package to map $id to an in-game action."
        'author=boyl'
    ) -join "`n"
    $modInfo | Set-Content -LiteralPath (Join-Path $stage 'modinfo.ini') -Encoding utf8NoBOM
    $zipPath = Join-Path $outputRoot "Lihuo-SnS-Diagnostic-$id.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -CompressionLevel Optimal
    $results += [ordered]@{ id = $id; sourceSha256 = $record.sha256; diagnosticSha256 = $newHash; package = $zipPath }

    $prototypeTarget = Join-Path $prototypeStage $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $prototypeTarget) -Force | Out-Null
    Copy-Item -LiteralPath $target -Destination $prototypeTarget
}

$prototypeInfo = @(
    'name=Lihuo SnS Core Prototype'
    'version=0.1.0-prototype'
    'description=First fire-palette direction prototype; all Sword and Shield specific EFX.'
    'author=boyl'
) -join "`n"
$prototypeInfo | Set-Content -LiteralPath (Join-Path $prototypeStage 'modinfo.ini') -Encoding utf8NoBOM
$prototypeZip = Join-Path (Split-Path -Parent $outputRoot) 'Lihuo-SnS-Core-0.1.0-prototype.zip'
if (Test-Path -LiteralPath $prototypeZip) { Remove-Item -LiteralPath $prototypeZip -Force }
Compress-Archive -Path (Join-Path $prototypeStage '*') -DestinationPath $prototypeZip -CompressionLevel Optimal
& (Join-Path $PSScriptRoot 'Test-Package.ps1') -PackagePath $prototypeZip -Variant Core

$resultPath = Join-Path $outputRoot 'diagnostic-manifest.json'
[ordered]@{
    schemaVersion = 1
    primaryColor = $PrimaryColor
    secondaryColor = $SecondaryColor
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    corePrototype = $prototypeZip
    packages = $results
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding utf8NoBOM
Write-Output 'LIHUO_DIAGNOSTICS=OK'
Write-Output "MANIFEST=$resultPath"
