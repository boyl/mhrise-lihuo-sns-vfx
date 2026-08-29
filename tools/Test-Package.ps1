[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][ValidateSet('Core', 'Enhanced')][string]$Variant,
    [string]$OriginalManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OriginalManifestPath) { $OriginalManifestPath = Join-Path $repoRoot '.work\original-manifest.json' }
$originalHashes = @{}
if (Test-Path -LiteralPath $OriginalManifestPath) {
    $manifest = Get-Content -LiteralPath $OriginalManifestPath -Raw | ConvertFrom-Json
    foreach ($file in $manifest.files) { $originalHashes[$file.sha256] = $file.path }
}
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath))
try {
    $entries = @($zip.Entries | Where-Object { $_.FullName -and -not $_.FullName.EndsWith('/') })
    foreach ($entry in $entries) {
        $path = $entry.FullName.Replace('\\', '/')
        $allowed = $path -eq 'modinfo.ini' -or
            $path -match '^natives/STM/vfx/editor/efd_pl/efd_s-swd/[^/]+\.efx\.2818730$' -or
            ($Variant -eq 'Enhanced' -and $path -match '^reframework/autorun/LihuoSnSVfx/[^/]+\.lua$')
        if (-not $allowed) { throw "包内存在越界文件：$path" }
        if ($path -match '\.(dll|exe|pak)$') { throw "包内禁止第三方二进制：$path" }
        if ($path -match '\.efx\.2818730$' -and $originalHashes.Count -gt 0) {
            $stream = $entry.Open()
            try {
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $hash = [Convert]::ToHexString($sha.ComputeHash($stream)) }
                finally { $sha.Dispose() }
            }
            finally { $stream.Dispose() }
            if ($originalHashes.ContainsKey($hash)) { throw "包内 EFX 与原始游戏文件完全相同：$path" }
        }
    }
    $efxCount = @($entries | Where-Object { $_.FullName -match '\.efx\.2818730$' }).Count
    if ($efxCount -ne 10) { throw "包内 EFX 数量应为 10，实际=$efxCount。" }
    if ($Variant -eq 'Core' -and @($entries | Where-Object { $_.FullName -match '^reframework/' }).Count -gt 0) {
        throw 'Core 包不得包含 REFramework 文件。'
    }
}
finally { $zip.Dispose() }
Write-Output "LIHUO_PACKAGE_VALIDATION=OK"
