# 首轮原型使用说明

## 最快确认视觉方向

开发验收优先解压 `dist/Lihuo-SnS-Core-0.1.0-prototype-Installer.zip`，完全退出游戏后双击 `INSTALL.cmd`。安装器只写入清单中的 10 个片手 EFX，并在完成前逐一复核 SHA-256；重复运行不会重复叠加文件。也可使用 Fluffy Mod Manager 安装 `dist/Lihuo-SnS-Core-0.1.0-prototype.zip`。两种方式只能选择一种，并确认没有同时启用任何诊断包或 Enhanced 包。

进入训练场后依次录制：

1. 普通连段；
2. 回旋斩及连段终结；
3. 风车；
4. 灭昇龙；
5. 下砸与空中派生。

本包只验证赤红主色与金色辅色是否适合作为“离火”方向，尚未按动作区分亮度、尺寸和寿命。

## 建立文件—动作映射

禁用 Core 原型，一次只启用 `dist/diagnostics/` 下的一个包。每个包只修改一个片手 EFX；看到变色后记录具体动作、触发阶段和是否重复。

诊断包之间互斥。更换诊断包前先在 Fluffy 中禁用当前包，避免无法判断来源。

## 动作探针

`dist/Lihuo-SnS-Action-Probe-0.1.0-probe.zip` 只用于开发映射，要求 REFramework。输出位于：

`reframework/data/LihuoSnSVfx-action-probe.json`

探针只记录片手动作状态机迁移；它不修改伤害、动作、存档或网络状态，也不生成特效。

## 回退

使用开发安装器时，完全退出游戏后双击同一目录中的 `UNINSTALL.cmd`；卸载器会先核对当前安装文件，拒绝覆盖测试期间被其他 Mod 改写的文件，并恢复安装前备份。使用 Fluffy 时，在 Fluffy 中禁用或卸载候选包即可恢复原始 EFX。若同时安装过其他特效 Mod，先由 Fluffy 执行重新读取游戏存档/文件，再只启用一个候选进行对照。
