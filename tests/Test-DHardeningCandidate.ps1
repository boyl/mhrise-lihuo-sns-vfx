#Requires -Version 7.0
[CmdletBinding()]
param([string]$SourcePackage = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourcePackage)) {
    $SourcePackage = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\烈焰片手剑2.0.zip'
}
$ExpectedSourceSha = '7DBD0EFDE0322CF30FDD355CE3C2DF8DF7BC6B114C6969C9B379B642FCE9738C'
$fixtureRoot = Join-Path $repoRoot ('.work\tests\d-hardening-' + [guid]::NewGuid().ToString('N'))
$packageOne = Join-Path $fixtureRoot 'candidate-one.zip'
$packageTwo = Join-Path $fixtureRoot 'candidate-two.zip'
$expanded = Join-Path $fixtureRoot 'expanded'

function Get-Sha([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-FixtureFile([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    Set-Content -LiteralPath $Path -Value $Text -Encoding utf8NoBOM
}

function New-FakeGameRoot([string]$Name) {
    $root = Join-Path $fixtureRoot $Name
    [IO.Directory]::CreateDirectory($root) | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'MonsterHunterRise.exe') -Value 'fixture' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root '.lihuo-isolated-test-root') -Value 'fixture' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $root 'dinput8.dll') -Value 'fixture REFramework' -Encoding ascii
    Write-FixtureFile (Join-Path $root 'reframework\plugins\FirstNatives.dll') 'fixture FirstNatives'
    Write-FixtureFile (Join-Path $root 'reframework\autorun\yunwulian\yun_modules.lua') 'fixture yun_modules'
    $root
}

function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

Add-Type -AssemblyName System.IO.Compression
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
try {
    if (-not (Test-Path -LiteralPath $SourcePackage -PathType Leaf)) { throw "缺少 D 输入包：$SourcePackage" }
    if ((Get-Sha $SourcePackage) -ne $ExpectedSourceSha) { throw 'D 输入包 SHA-256 漂移。' }

    & (Join-Path $repoRoot 'tools\Build-DHardeningCandidate.ps1') -SourcePackage $SourcePackage -OutputPath $packageOne
    & (Join-Path $repoRoot 'tools\Build-DHardeningCandidate.ps1') -SourcePackage $SourcePackage -OutputPath $packageTwo
    if ((Get-Sha $packageOne) -ne (Get-Sha $packageTwo)) { throw 'D-hardening 构建结果不确定。' }

    [IO.Compression.ZipFile]::ExtractToDirectory($packageOne, $expanded)
    $manifestPath = Join-Path $expanded 'payload-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schema_version -ne 1 -or
        $manifest.policy -ne 'transactional_allowlisted_d_hardening_local_only' -or
        $manifest.package_id -ne 'lihuo-sns-d-hardening' -or
        $manifest.package_ready -ne $true -or $manifest.real_game_install_permitted -ne $true -or
        @($manifest.files).Count -ne 87 -or $manifest.runtime_contract.network_sync -ne $false -or
        [int]$manifest.runtime_contract.hook_count -ne 1 -or $manifest.runtime_contract.original_script_included -ne $false) {
        throw 'D-hardening manifest 身份或安全契约无效。'
    }
    $nativeRecords = @($manifest.files | Where-Object path -like 'natives/*')
    if ($nativeRecords.Count -ne 84 -or @($nativeRecords | Where-Object path -notlike 'natives/STM/vfx/*').Count -ne 0) {
        throw 'D-hardening 不是已审计的完整 Provider loose 闭包。'
    }
    if ((Test-Path -LiteralPath (Join-Path $expanded 'reframework\autorun\ShortSwordVfx.lua') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $expanded 'reframework\autorun\ShortSwordVfx.txt') -PathType Leaf)) {
        throw 'D-hardening 错误包含原 ShortSwordVfx 文件。'
    }

    $modulePath = Join-Path $expanded 'reframework\autorun\LihuoSnSVfx\d_hardening_candidate.lua'
    $module = Get-Content -LiteralPath $modulePath -Raw -Encoding UTF8
    if ([regex]::Matches($module, 'sdk\.hook\(').Count -ne 1) { throw 'D-hardening 必须且只能注册一个 Hook。' }
    if ([regex]::Matches($module, 'yun\.set_effect\(').Count -ne 1 -or
        $module -notmatch 'yun\.set_effect\(EXPECTED_CONTAINER_ID, effect_id, false\)') {
        throw 'D-hardening 的所有 set_effect 调用必须通过单一边界并显式 sync=false。'
    }
    if ([regex]::Matches($module, 'yun\.set_effect_with_instance\(').Count -ne 1 -or
        $module -notmatch 'yun\.set_effect_with_instance\(EXPECTED_CONTAINER_ID, effect_id, false\)' -or
        $module -notmatch 'instance:finishAll\(\)' -or $module -notmatch 'instance:force_release\(\)') {
        throw 'D-hardening 持续效果必须通过单一实例边界创建并在动作边界强制释放。'
    }
    foreach ($required in @(
        'EXPECTED_CONTAINER_ID = 150', 'state.recipes["100:108"]',
        'd_provider_local_only_full_sns_recipe_exact_hit',
        'calc_result:get_AttackerID()', 'calc_result:get_WeaponType()',
        'damage_attacker_id ~= player_index', 'state.tick - state.last_eligible_action_tick <= config.hit_grace_ticks',
        'result ~= true', 'release_active_instances("script-reset")', 'active_instance_count',
        're.on_script_reset'
    )) {
        if (-not $module.Contains($required)) { throw "D-hardening Lua 缺少契约：$required" }
    }
    foreach ($forbidden in @(
        'sendSingleEffectCallPacket', 'push_effect_table', 'setItemEffect',
        'sdk.call_native_func', 'os.execute', 'io.popen', 'loadfile(', 'dofile('
    )) {
        if ($module.Contains($forbidden)) { throw "D-hardening Lua 包含禁止能力：$forbidden" }
    }

    $config = Get-Content -LiteralPath (Join-Path $expanded 'reframework\data\LihuoSnSVfx-d-hardening.json') -Raw | ConvertFrom-Json
    $baselineRecipe = @($config.recipes | Where-Object { [int]$_.action_id -eq 108 })
    $persistentEffectIds = @(24021, 24022, 24044, 24049, 24050, 24051)
    $unsafeRecipes = @($config.recipes | Where-Object {
        ($persistentEffectIds -contains [int]$_.hit_effect_id) -or
        ($_.whiff_mode -eq 'one_shot' -and $persistentEffectIds -contains [int]$_.whiff_effect_id) -or
        ($_.whiff_mode -eq 'instance' -and $persistentEffectIds -notcontains [int]$_.whiff_effect_id)
    })
    $instanceRecipes = @($config.recipes | Where-Object whiff_mode -eq 'instance')
    $instanceMotions = @($instanceRecipes | ForEach-Object { [int]$_.action_id } | Sort-Object)
    if ($config.schema_version -ne 2 -or $config.enabled -ne $true -or $config.network_sync -ne $false -or
        [int]$config.weapon_type -ne 8 -or [int]$config.action_bank -ne 100 -or
        [int]$config.container_id -ne 150 -or @($config.recipes).Count -ne 39 -or
        $baselineRecipe.Count -ne 1 -or [int]$baselineRecipe[0].whiff_effect_id -ne 24007 -or
        [int]$baselineRecipe[0].hit_effect_id -ne 30007 -or $unsafeRecipes.Count -ne 0 -or
        ($instanceMotions -join ',') -ne '114,115,117,182' -or
        [int](@($instanceRecipes | Where-Object action_id -eq 114)[0].whiff_effect_id) -ne 24021 -or
        [int](@($instanceRecipes | Where-Object action_id -eq 117)[0].whiff_effect_id) -ne 24051 -or
        [int](@($instanceRecipes | Where-Object action_id -eq 182)[0].whiff_effect_id) -ne 24044 -or
        [int](@($instanceRecipes | Where-Object action_id -eq 182)[0].finish_effect_id) -ne 25044 -or
        [int]$config.hit_grace_ticks -ne 12) {
        throw 'D-hardening 运行配置漂移。'
    }

    $gameRoot = New-FakeGameRoot 'game-transaction'
    $seedRecord = $nativeRecords[0]
    $seedTarget = Join-Path $gameRoot ([string]$seedRecord.path).Replace('/', '\')
    Write-FixtureFile $seedTarget 'original preimage'
    $seedSha = Get-Sha $seedTarget
    $install = Join-Path $expanded 'Install.ps1'
    & $install -GameRoot $gameRoot -AllowRunningGameForIsolatedTest
    $stateRoot = Join-Path $gameRoot '_lihuo_sns_vfx_d_hardening'
    $installedManifestPath = Join-Path $stateRoot 'install-manifest.json'
    $installed = Get-Content -LiteralPath $installedManifestPath -Raw | ConvertFrom-Json
    if ($installed.status -ne 'installed' -or @($installed.files).Count -ne 87 -or
        -not (Test-Path -LiteralPath (Join-Path $stateRoot 'Rollback.ps1') -PathType Leaf)) {
        throw 'D-hardening 假根安装状态不完整。'
    }
    foreach ($record in @($installed.files)) {
        $target = Join-Path $gameRoot ([string]$record.path).Replace('/', '\')
        if ((Get-Sha $target) -ne ([string]$record.installed_sha256).ToUpperInvariant()) {
            throw "D-hardening 安装哈希错误：$($record.path)"
        }
    }
    & $install -GameRoot $gameRoot -AllowRunningGameForIsolatedTest | Out-Null

    $nonSeeded = @($installed.files | Where-Object { -not [bool]$_.preexisting })[0]
    $driftTarget = Join-Path $gameRoot ([string]$nonSeeded.path).Replace('/', '\')
    $control = @($installed.files | Where-Object path -ne $nonSeeded.path)[0]
    $controlTarget = Join-Path $gameRoot ([string]$control.path).Replace('/', '\')
    $controlSha = Get-Sha $controlTarget
    Set-Content -LiteralPath $driftTarget -Value 'drift' -Encoding ascii
    $rollback = Join-Path $stateRoot 'Rollback.ps1'
    Assert-Throws { & $rollback -GameRoot $gameRoot -AllowRunningGameForIsolatedTest } '回滚没有拒绝已安装文件漂移。'
    if ((Get-Sha $controlTarget) -ne $controlSha -or -not (Test-Path -LiteralPath $installedManifestPath)) {
        throw '回滚漂移预检后发生了部分写入。'
    }
    Copy-Item -LiteralPath (Join-Path $expanded ([string]$nonSeeded.path).Replace('/', '\')) -Destination $driftTarget -Force
    & $rollback -GameRoot $gameRoot -AllowRunningGameForIsolatedTest
    if (Test-Path -LiteralPath $stateRoot) { throw 'D-hardening 回滚后仍残留状态目录。' }
    if ((Get-Sha $seedTarget) -ne $seedSha) { throw 'D-hardening 未恢复已有目标。' }
    if (Test-Path -LiteralPath $driftTarget) { throw 'D-hardening 未删除原本不存在的目标。' }

    $conflictRoot = New-FakeGameRoot 'game-conflict'
    Write-FixtureFile (Join-Path $conflictRoot '_lihuo_sns_vfx_yun_visual\install-manifest.json') '{}'
    Assert-Throws { & $install -GameRoot $conflictRoot -AllowRunningGameForIsolatedTest } '安装器未拒绝活动 C 候选。'
    if (Test-Path -LiteralPath (Join-Path $conflictRoot '_lihuo_sns_vfx_d_hardening')) {
        throw '冲突拒绝后错误创建了 D-hardening 状态。'
    }

    $tamperedRoot = New-FakeGameRoot 'game-tampered-payload'
    $tamperedModule = Join-Path $expanded 'reframework\autorun\LihuoSnSVfx\d_hardening_candidate.lua'
    Add-Content -LiteralPath $tamperedModule -Value '-- drift' -Encoding utf8NoBOM
    Assert-Throws { & $install -GameRoot $tamperedRoot -AllowRunningGameForIsolatedTest } '安装器未拒绝候选载荷漂移。'
    if (Test-Path -LiteralPath (Join-Path $tamperedRoot '_lihuo_sns_vfx_d_hardening')) {
        throw '载荷漂移拒绝后错误创建了安装状态。'
    }

    $tamperedSource = Join-Path $fixtureRoot 'tampered-source.zip'
    [IO.File]::WriteAllBytes($tamperedSource, [IO.File]::ReadAllBytes($SourcePackage) + [byte]0)
    Assert-Throws {
        & (Join-Path $repoRoot 'tools\Build-DHardeningCandidate.ps1') -SourcePackage $tamperedSource -OutputPath (Join-Path $fixtureRoot 'must-not-exist.zip')
    } '构建器未在解压前拒绝来源 SHA 漂移。'

    'LIHUO_D_HARDENING_TESTS=OK'
    "PACKAGE_SHA256=$(Get-Sha $packageOne)"
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
