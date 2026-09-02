#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePackage,
    [string]$OutputPath = '',
    [string]$Version = '0.5.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ExpectedSourceSha = '7DBD0EFDE0322CF30FDD355CE3C2DF8DF7BC6B114C6969C9B379B642FCE9738C'
$Policy = 'transactional_allowlisted_d_hardening_local_only'
$PackageId = 'lihuo-sns-d-hardening'
$NativePaths = @()
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "dist\Lihuo-SnS-D-Hardening-$Version.zip"
}
if (-not (Test-Path -LiteralPath $SourcePackage -PathType Leaf)) { throw "找不到 D 输入包：$SourcePackage" }
if ((Get-FileHash -LiteralPath $SourcePackage -Algorithm SHA256).Hash -ne $ExpectedSourceSha) {
    throw 'D 输入包 SHA-256 不等于已审计版本。'
}

function Find-Bytes([byte[]]$Haystack, [byte[]]$Needle) {
    for ($offset = 0; $offset -le $Haystack.Length - $Needle.Length; $offset++) {
        $match = $true
        for ($index = 0; $index -lt $Needle.Length; $index++) {
            if ($Haystack[$offset + $index] -ne $Needle[$index]) { $match = $false; break }
        }
        if ($match) { return $offset }
    }
    -1
}

function Get-RelativePath([string]$Root, [string]$Path) {
    [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
}

Add-Type -AssemblyName System.IO.Compression
$stage = Join-Path $repoRoot ('.work\build-d-hardening-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
try {
    $inputStream = [IO.File]::OpenRead($SourcePackage)
    $archive = [IO.Compression.ZipArchive]::new($inputStream, [IO.Compression.ZipArchiveMode]::Read, $false)
    try {
        $fileEntries = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
        if ($fileEntries.Count -ne 86) { throw "D 已审计输入文件数漂移：$($fileEntries.Count)" }
        $entryMap = @{}
        foreach ($entry in $fileEntries) {
            $path = $entry.FullName.Replace('\', '/')
            if ([IO.Path]::IsPathRooted($path) -or $path.Contains('..') -or $path.Contains(':')) {
                throw "D 输入包含不安全路径：$path"
            }
            $key = $path.ToLowerInvariant()
            if ($entryMap.ContainsKey($key)) { throw "D 输入包含重复路径：$path" }
            $entryMap[$key] = $entry
        }
        $NativePaths = @($fileEntries |
            Where-Object { $_.FullName.Replace('\', '/') -like 'natives/*' } |
            ForEach-Object { $_.FullName.Replace('\', '/') } |
            Sort-Object)
        if ($NativePaths.Count -ne 84) {
            throw "D 完整原生资源闭包应为 84 文件，实际为 $($NativePaths.Count)。"
        }
        foreach ($relative in $NativePaths) {
            $key = $relative.ToLowerInvariant()
            if (-not $entryMap.ContainsKey($key)) { throw "D 输入缺少最小资源闭包：$relative" }
            $entry = $entryMap[$key]
            if ($entry.Length -le 0 -or $entry.Length -gt 2MB) { throw "D 资源大小异常：$relative" }
            $target = [IO.Path]::GetFullPath((Join-Path $stage $relative.Replace('/', '\')))
            [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
            $source = $entry.Open()
            $destination = [IO.File]::Create($target)
            try { $source.CopyTo($destination) }
            finally { $destination.Dispose(); $source.Dispose() }
        }
    }
    finally { $archive.Dispose(); $inputStream.Dispose() }

    function New-Recipe([int]$ActionId, [string]$Name, [string]$Tier,
        [int]$WhiffEffectId, [int]$HitEffectId, [int]$MaxHitEffects = 1,
        [ValidateSet('one_shot', 'instance')][string]$WhiffMode = 'one_shot',
        [int]$FinishEffectId = 0) {
        $recipe = [ordered]@{
            action_id = $ActionId; name = $Name; tier = $Tier
            whiff_effect_id = $WhiffEffectId; hit_effect_id = $HitEffectId
            max_hit_effects = $MaxHitEffects; whiff_mode = $WhiffMode
            finish_effect_id = if ($FinishEffectId -gt 0) { $FinishEffectId } else { $null }
        }
        $recipe
    }
    $Recipes = @(
        New-Recipe 101 '劈斩' normal 24000 30000
        New-Recipe 102 '横斩' normal 24001 30001
        New-Recipe 103 '剑盾连击' normal 24002 30002 2
        New-Recipe 104 '水平斩' normal 24003 30003
        New-Recipe 105 '回斩' normal 24004 30004
        New-Recipe 106 '回旋上捞斩' normal 24005 30005
        New-Recipe 107 '回旋斩' finisher 24006 30006
        New-Recipe 108 '旋风刈' finisher 24007 30007
        New-Recipe 123 '盾攻击' normal 24008 30008
        New-Recipe 125 '奋力强锤' finisher 24010 30010
        New-Recipe 181 '双连剑连击' finisher 24011 30011 2
        New-Recipe 131 '滑行斩' finisher 24012 30012
        New-Recipe 120 '突进斩' normal 24013 30013
        New-Recipe 121 '上捞斩' normal 24014 30014
        New-Recipe 128 '跳跃上捞斩' finisher 24015 30015
        New-Recipe 126 '跳跃斩' finisher 24016 30016
        New-Recipe 129 '跳跃突进斩' finisher 24018 30018
        New-Recipe 112 '上冲斩一段' signature 24019 30019
        New-Recipe 113 '上冲斩二段' signature 24019 30019
        New-Recipe 137 '飞影' signature 24020 30020
        New-Recipe 114 '下坠强锤一段' signature 24021 30021 2 instance
        New-Recipe 115 '下坠强锤二段' signature 24021 30021 2 instance
        New-Recipe 117 '下坠突刺' signature 24051 30051 3 instance
        New-Recipe 119 '下坠突刺砸地' signature 24052 30051
        New-Recipe 116 '下坠强锤砸地' signature 24023 24024 2
        New-Recipe 156 '致命连击一段' finisher 24028 30028 2
        New-Recipe 157 '致命连击二段' finisher 24030 30028 3
        New-Recipe 158 '致命连击三段' finisher 24034 30034 3
        New-Recipe 122 '防御斩' finisher 24041 30007
        New-Recipe 111 '蓄力斩' signature 24046 30007
        New-Recipe 140 '灭昇龙一段' signature 24043 30043
        New-Recipe 154 '灭昇龙强化一段' signature 24043 30043 4
        New-Recipe 141 '灭昇龙二段' signature 24143 30043
        New-Recipe 155 '灭昇龙强化二段' signature 25143 30043 4
        New-Recipe 182 '盾牌猛击' finisher 24044 30044 1 instance 25044
        New-Recipe 183 '重击刃药' signature 24007 30007
        New-Recipe 135 '风车' signature 24053 30053 8
        New-Recipe 134 '穿斩' signature 24054 30054 3
        New-Recipe 133 '突刺' signature 24055 30055
    )
    if (@($Recipes.action_id | Sort-Object -Unique).Count -ne $Recipes.Count) {
        throw 'D 动作配方包含重复 Motion ID。'
    }
    $persistentEffectIds = @(24021, 24022, 24044, 24049, 24050, 24051)
    $unsafeRecipes = @($Recipes | Where-Object {
        ($persistentEffectIds -contains [int]$_.hit_effect_id) -or
        ($_.whiff_mode -eq 'one_shot' -and $persistentEffectIds -contains [int]$_.whiff_effect_id) -or
        ($_.whiff_mode -eq 'instance' -and $persistentEffectIds -notcontains [int]$_.whiff_effect_id) -or
        ($null -ne $_.finish_effect_id -and $persistentEffectIds -contains [int]$_.finish_effect_id)
    })
    if ($unsafeRecipes.Count -gt 0) {
        throw "D 配方的一次性/实例生命周期声明不一致：$($unsafeRecipes.name -join '、')"
    }

    $providerRelative = 'natives/STM/vfx/provider/epv_pl/epv_s-swd/epvs-prg_0004_s-swd_00_0000.pfb.17'
    $providerPath = Join-Path $stage $providerRelative.Replace('/', '\')
    $providerBytes = [IO.File]::ReadAllBytes($providerPath)
    foreach ($effectId in @(24007, 30007)) {
        if ((Find-Bytes $providerBytes ([BitConverter]::GetBytes([int]$effectId))) -lt 0) {
            throw "D provider 未包含已审计 EffectID：$effectId"
        }
    }

    $autorunRoot = Join-Path $stage 'reframework\autorun'
    $moduleRoot = Join-Path $autorunRoot 'LihuoSnSVfx'
    $dataRoot = Join-Path $stage 'reframework\data'
    [IO.Directory]::CreateDirectory($moduleRoot) | Out-Null
    [IO.Directory]::CreateDirectory($dataRoot) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'enhanced-runtime\reframework\autorun\LihuoSnSVfxDHardening.lua') -Destination $autorunRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot 'enhanced-runtime\reframework\autorun\LihuoSnSVfx\d_hardening_candidate.lua') -Destination $moduleRoot

    $providerSha = (Get-FileHash -LiteralPath $providerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        schema_version = 2
        enabled = $true
        weapon_type = 8
        action_bank = 100
        container_id = 150
        network_sync = $false
        default_whiff_trigger_frame = 3
        default_whiff_max_late_frames = 5
        hit_grace_ticks = 12
        recipes = $Recipes
        evidence = [ordered]@{
            source_archive_sha256 = $ExpectedSourceSha.ToLowerInvariant()
            provider_sha256 = $providerSha
            baseline_provider_contains_effect_ids = @(24007, 30007)
            native_closure = $NativePaths
            recipe_source = 'audited ShortSwordVfx 2.0 action/effect contract; implementation rewritten locally'
            hit_source_signature = 'afterCalcDamage_DamageSide(snow.hit.DamageFlowInfoBase,snow.DamageReceiver.HitInfo)'
        }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dataRoot 'LihuoSnSVfx-d-hardening.json') -Encoding utf8NoBOM

    $payloadPaths = @($NativePaths) + @(
        'reframework/autorun/LihuoSnSVfxDHardening.lua',
        'reframework/autorun/LihuoSnSVfx/d_hardening_candidate.lua',
        'reframework/data/LihuoSnSVfx-d-hardening.json'
    )
    $payloadFiles = @($payloadPaths | ForEach-Object {
        $payloadPath = Join-Path $stage $_.Replace('/', '\')
        [ordered]@{
            path = $_
            sha256 = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
            size = (Get-Item -LiteralPath $payloadPath).Length
        }
    })
    $identityText = ($payloadFiles | ForEach-Object { "$($_.path)|$($_.sha256)|$($_.size)" }) -join "`n"
    $identity = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identityText))
    ).ToLowerInvariant()
    [ordered]@{
        schema_version = 1
        policy = $Policy
        package_id = $PackageId
        package_version = $Version
        package_sha256 = $identity
        source_archive_sha256 = $ExpectedSourceSha.ToLowerInvariant()
        package_ready = $true
        real_game_install_permitted = $true
        dependencies = @('REFramework', 'FirstNatives', 'yunwulian.yun_modules')
        runtime_contract = [ordered]@{
            local_only = $true
            network_sync = $false
            hook_count = 1
            action = "Bank100 data-driven Sword & Shield recipes ($($Recipes.Count) motions)"
            hit_authentication = 'DamageFlowInfoBase.get_AttackerID/get_WeaponType exact match'
            baseline_effect_pair = @('150:24007', '150:30007')
            recipe_count = $Recipes.Count
            original_script_included = $false
        }
        files = $payloadFiles
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $stage 'payload-manifest.json') -Encoding utf8NoBOM

    Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\package\d-hardening\Install.ps1') -Destination (Join-Path $stage 'Install.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\package\d-hardening\Uninstall.ps1') -Destination (Join-Path $stage 'Uninstall.ps1')
    @(
        "离火片手攻击特效 $Version"
        ''
        "用途：覆盖片手 Bank100 的 $($Recipes.Count) 个已审计攻击动作，分别派发空击与命中特效。"
        '动作配方分为普通、终结和招牌三级；Motion108（旋风刈）仍作为基准验证配方。'
        '所有 set_effect 调用显式 sync=false，不发送网络特效。'
        '正式包包含已审计输入的 84 个原生资源完整闭包，以及我方 loader/module/config；不包含或执行原 ShortSwordVfx.lua。'
        '前置：REFramework、FirstNatives、yun_modules。安装器拒绝 A/B/C/原 D 混装并提供事务回滚。'
        ''
        '手动安装：完全退出游戏，把本压缩包内的 natives 和 reframework 两个文件夹复制到 MonsterHunterRise.exe 所在目录并合并。'
        '不要把压缩包名称目录整体套在游戏目录下；最终应存在 MonsterHunterRise\natives\STM\vfx 和 MonsterHunterRise\reframework\autorun。'
        '推荐安装：已安装 PowerShell 7 的用户可在解压目录运行 pwsh -File .\Install.ps1；它会检查前置、冲突、哈希并保存回滚数据。'
        '手动卸载：完整退出游戏，按 MANUAL-FILES.txt 删除本包文件；若文件被其他 Mod 共用或覆盖，先恢复备份，不要删除整个 natives/reframework。'
        ''
        '实机门禁：进入修炼场，分别验证普通连斩、飞影、旋风刈、风车与灭昇龙的空击和命中。'
        '证据：reframework/data/LihuoSnSVfx-d-hardening-result.json。'
    ) | Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Encoding utf8NoBOM
    $payloadPaths | Set-Content -LiteralPath (Join-Path $stage 'MANUAL-FILES.txt') -Encoding utf8NoBOM

    [IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath)))) | Out-Null
    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
    $outputStream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew)
    $resultArchive = [IO.Compression.ZipArchive]::new($outputStream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object { Get-RelativePath $stage $_.FullName }) {
            $relative = Get-RelativePath $stage $file.FullName
            $entry = $resultArchive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $input = [IO.File]::OpenRead($file.FullName)
            $output = $entry.Open()
            try { $input.CopyTo($output) }
            finally { $output.Dispose(); $input.Dispose() }
        }
    }
    finally { $resultArchive.Dispose(); $outputStream.Dispose() }

    $packageSha = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash
    'LIHUO_D_HARDENING_BUILD=OK'
    "PACKAGE=$([IO.Path]::GetFullPath($OutputPath))"
    "PACKAGE_SHA256=$packageSha"
    "PAYLOAD_ID=$identity"
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
