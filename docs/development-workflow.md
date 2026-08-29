# 开发与候选验证流程

## 1. 固定运行时

`Extract-CoreAssets.ps1` 默认只接受 Steam 版 16.0.2.0 和已记录的游戏程序 SHA-256。基础 PAK 先提取，补丁 PAK 按编号覆盖，最终必须得到允许列表中的 10 个文件。

原始文件和清单位于 `.work/`，不纳入 Git。游戏更新后不得复用旧清单。

## 2. 准备 EFX 工具链

开发机安装 010 Editor；从锁定提交自行取得以下文件：

- 仓库：`https://github.com/NSACloud/MHR-EFX-Template`
- 提交：`cfb34d4c7448935ddc5d35b0ba1acfdfda2d1359`
- `RISE_EFX.bt`
- `EFX_COLOR_CHANGE.1sc`

放入 `.work/third-party/MHR-EFX-Template/` 后运行 `Test-EfxToolchain.ps1`。工具会核对哈希，第三方文件不会进入源码和分发包。

## 3. 生成诊断包

`New-DiagnosticPrototypes.ps1` 会：

1. 将第三方交互调色脚本转换为仅存在于 `.work/` 的无交互副本；
2. 逐个修改 10 个 EFX；
3. 检查文件大小不变且 SHA-256 已变化；
4. 生成 10 个互斥单文件诊断包；
5. 生成包含全部 10 个文件的 Core 视觉方向原型；
6. 审计 Core 包允许列表并阻止未修改原文件进入包。

## 4. 实机映射

一次只启用一个诊断包。固定训练场、片手装备、替换技和摄像机，执行主要动作并更新 `docs/effect-map.md`。需要动作状态证据时安装 Action Probe；它只读记录状态迁移，不生成特效。

映射确认后，才按 `visual-tiers.json` 分别调校普通、终结和招牌动作。不能用旧 Wiki 名称替代实机验证。

## 5. 最终构建

将通过验收的 10 个修改文件放入 `core-assets/natives/`，再运行 `Build-Packages.ps1`。Core 验收前不连接增强派发器；增强版失败时不影响 Core 的交付。
