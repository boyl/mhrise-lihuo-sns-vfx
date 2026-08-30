# 离火片手攻击特效 Mod

面向 Steam《怪物猎人：崛起：曙光》16.0.2.0 的片手剑本地视觉 Mod。项目只重编排游戏原生火焰、余烬、刀光与爆燃组件，不改变伤害、动作、判定、网络状态或存档。

## 当前阶段

- 已建立独立提取、哈希、动作映射、构建和包验证链路。
- 当前公开下载物是 `0.4.0` 只读诊断包，需要 REFramework，**不会显示离火特效**。
- 早期 `Core` 纯资源原型命中了豪鬼外观专用 EFX，不能满足“所有片手剑、不依赖外观”的目标，已停止作为可用方案分发。
- 正式版将基于游戏实际创建的有效效果上下文实现；完成实机可见效果前不发布稳定版。
- 两个版本最终互斥，不得同时安装。

## 下载与安装

- 下载页面：[GitHub Releases](https://github.com/boyl/mhrise-lihuo-sns-vfx/releases)。
- 当前文件：`Lihuo-SnS-Action-Probe-0.4.0-diagnostic.zip`。
- 完整步骤：[安装、手动复制、卸载与诊断报告](docs/installation.md)。

> 当前诊断包的成功标准是生成 JSON 报告，不是出现火焰特效。需要可见离火效果的玩家请等待正式候选版。

## 目录

- `core-assets/`：修改后的片手专属 EFX 与视觉配方。
- `enhanced-runtime/`：REFramework 动作探针及后续派发边界。
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

生成真正的视觉原型还需要本机安装 010 Editor，并由开发者单独取得 `MHR-EFX-Template`。第三方模板不复制到本仓库，也不是玩家安装前置。

完整流程见 [开发与候选验证流程](docs/development-workflow.md)，首轮实机操作见 [原型验收说明](docs/prototype-acceptance.md)。

## 许可与资产

项目原创脚本和文档使用 MIT License。游戏资源及其修改版本仍受原权利人条款约束，详见 [ASSET-NOTICE.md](ASSET-NOTICE.md)。
