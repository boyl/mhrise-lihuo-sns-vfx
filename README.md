# 离火片手攻击特效 Mod

面向 Steam《怪物猎人：崛起：曙光》16.0.2.0 的片手剑本地视觉 Mod。当前 D 候选对所有片手剑生效，不依赖指定武器或防具外观；它只改变本机攻击视觉，不修改伤害、动作、判定、网络状态或存档。

## 当前下载

- 版本：`v0.5.0-d-candidate.1`。
- 文件：`Lihuo-SnS-D-Hardening-0.5.0-d-candidate.1.zip`。
- 下载：[GitHub Releases](https://github.com/boyl/mhrise-lihuo-sns-vfx/releases)。
- 完整步骤：[安装、手动复制、验证、卸载与故障排查](docs/installation.md)。

这是公开候选版，不是最终稳定版。已经实机验证飞影空击/命中、升龙与下坠持续效果释放，以及 39/39 动作配方；发布前门禁仍保留长时间连续狩猎回归。

## 功能

- 覆盖 39 个片手 Bank100 攻击动作，分别派发空击与命中特效。
- 普通攻击、终结技和招牌动作使用不同强度的火焰、余烬、刀光与爆燃。
- 一次性效果由游戏回收；持续效果在动作切换、动作重启和脚本重载时显式释放。
- 所有派发均为本地视觉，不向联机队友同步特效。
- 内置事务安装、文件哈希校验、冲突拒绝与安全回滚。

## 前置要求

- [REFramework](https://github.com/praydog/REFramework)。
- [FirstNatives](https://www.nexusmods.com/monsterhunterrise/mods/848)。
- [yun_modules](https://github.com/yun-wulian/yun_modules)。

这些前置不会打包进本项目下载物。详细放置路径见安装文档。

## 目录

- `core-assets/`：片手 EFX 研究、映射与视觉配方。
- `enhanced-runtime/`：REFramework 动作识别、派发和生命周期边界。
- `tools/`：提取、工具链诊断、构建与包验证。
- `installer/`：Core 原型的可验证安装与安全卸载入口。
- `tests/`：离线契约测试。
- `docs/`：动作映射、开发步骤和人工验收。
- `.work/`：原始游戏资源与证据，不纳入 Git。
- `dist/`：候选包，不纳入 Git。

## 开发入口

```powershell
pwsh ./tools/Extract-CoreAssets.ps1
pwsh ./tools/Test-EfxToolchain.ps1
pwsh ./tools/New-DiagnosticPrototypes.ps1
pwsh ./tools/Build-ActionProbePackage.ps1
pwsh ./tools/Build-PrototypeInstaller.ps1
pwsh ./tests/Run-All.ps1
```

开发流程见 [开发与候选验证流程](docs/development-workflow.md)。010 Editor 和 EFX 模板只用于开发，不是玩家安装前置。

## 许可与资产

项目原创脚本和文档使用 MIT License。游戏资源及其修改版本仍受原权利人条款约束，详见 [ASSET-NOTICE.md](ASSET-NOTICE.md)。
