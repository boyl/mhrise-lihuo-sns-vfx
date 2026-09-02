# 安装、卸载与验证

本文适用于 `Lihuo-SnS-D-Hardening-0.5.0-d-candidate.1.zip`。该候选会显示离火攻击特效，但不会修改伤害、动作、判定、联机状态或存档。

## 系统和前置要求

- Steam 版《怪物猎人：崛起：曙光》16.0.2.0。
- [REFramework](https://github.com/praydog/REFramework)：非 VR 用户把官方压缩包中的 `dinput8.dll` 放到游戏根目录。
- [FirstNatives](https://www.nexusmods.com/monsterhunterrise/mods/848)：把 `FirstNatives.dll` 放到 `reframework\plugins`。
- [yun_modules](https://github.com/yun-wulian/yun_modules)：最终必须存在 `reframework\autorun\yunwulian\yun_modules.lua` 以及同级 `yun_modules` 子目录。

不需要指定防具、外观装备、武器皮肤或片手剑型号。

## 找到游戏根目录

在 Steam 库中右键《MONSTER HUNTER RISE》，选择“管理 → 浏览本地文件”。包含 `MonsterHunterRise.exe` 的文件夹就是游戏根目录。默认位置通常是：

```text
C:\Program Files (x86)\Steam\steamapps\common\MonsterHunterRise
```

## 手动安装（Nexus Mods 常用方式）

1. 完全退出游戏。
2. 安装并验证上面的三个前置。
3. 下载并解压 `Lihuo-SnS-D-Hardening-0.5.0-d-candidate.1.zip`。
4. 进入解压目录，只把其中的 `natives` 和 `reframework` 两个文件夹复制到游戏根目录。
5. Windows 询问时选择合并文件夹。若提示覆盖已有同路径 Mod 文件，先取消并移除冲突 Mod，不要盲目覆盖。
6. 启动游戏，装备任意片手剑进入修炼场。

正确的顶层结构如下：

```text
<游戏根目录>\
├─ MonsterHunterRise.exe
├─ dinput8.dll
├─ natives\
│  └─ STM\vfx\...
└─ reframework\
   ├─ plugins\FirstNatives.dll
   ├─ autorun\yunwulian\yun_modules.lua
   ├─ autorun\LihuoSnSVfxDHardening.lua
   ├─ autorun\LihuoSnSVfx\d_hardening_candidate.lua
   └─ data\LihuoSnSVfx-d-hardening.json
```

不要多套一层压缩包目录。下面这种路径是错误的：

```text
<游戏根目录>\Lihuo-SnS-D-Hardening-0.5.0-d-candidate.1\natives\...
```

## 自动安全安装（推荐给已安装 PowerShell 7 的用户）

完全退出游戏，在解压目录运行：

```powershell
pwsh -File .\Install.ps1 -GameRoot 'C:\Program Files (x86)\Steam\steamapps\common\MonsterHunterRise'
```

安装器会检查前置、候选冲突、87 个载荷文件的哈希，并为原有同路径文件建立事务备份。Steam 库不在默认位置时替换 `-GameRoot`。

## Nexus Mods / Mod 管理器准备

压缩包同时包含 `natives` 和 `reframework`，适合作为 Nexus Mods 的 Manual Download。管理器必须把两者部署到 `MonsterHunterRise.exe` 同级；若多套一层目录或不能同时部署脚本与资源，请改用手动安装。

## 如何确认已生效

进入修炼场后依次测试普通连斩、飞影空击/命中、旋风刈、风车和灭昇龙。应看到本地火焰、余烬、刀光或爆燃，而且停止攻击后不应残留永久燃烧。

运行报告位于：

```text
<游戏根目录>\reframework\data\LihuoSnSVfx-d-hardening-result.json
```

正常时 `active=true`、`recipe_audit_complete=true`、`valid_recipe_count=39`、`instance_release_failures=0`；结束持续动作后 `active_instance_count` 应回到 0。

## 卸载

如果使用 `Install.ps1` 安装，完全退出游戏后在原解压目录运行：

```powershell
pwsh -File .\Uninstall.ps1 -GameRoot 'C:\Program Files (x86)\Steam\steamapps\common\MonsterHunterRise'
```

它会恢复安装前已有文件并删除本包新增文件。

手动安装的用户应完全退出游戏，再按照压缩包中的 `MANUAL-FILES.txt` 逐项删除本包文件。至少需要删除：

```text
reframework\autorun\LihuoSnSVfxDHardening.lua
reframework\autorun\LihuoSnSVfx\d_hardening_candidate.lua
reframework\data\LihuoSnSVfx-d-hardening.json
```

同时删除 `MANUAL-FILES.txt` 列出的本包 `natives/STM/vfx/...` 文件。若安装前这些路径已有文件，必须恢复自己的备份。不要删除整个 `natives`、`reframework` 或 `dinput8.dll`。

## 故障排查

- 完全没有效果：确认三个前置的最终路径，检查 `re2_framework_log.txt` 中的 `[LihuoSnSVfx:DHardening]`。
- 启动即崩溃：先卸载本包和其他片手特效 Mod，单独验证 REFramework 与 FirstNatives，再逐个恢复。
- 只有部分动作有效：提交游戏版本、REFramework 版本、`re2_framework_log.txt` 和运行报告。
- 出现永久燃烧：停止继续测试并提交运行报告；正常情况下创建实例数应等于释放数，活动实例应归零。
- 不同游戏版本：停止使用，不要强行绕过安装门禁。
