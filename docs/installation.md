# 安装、卸载与诊断报告

## 当前下载包是什么

`Lihuo-SnS-Action-Probe-0.4.0-diagnostic.zip` 是开发阶段的只读诊断包，不是正式离火特效版。它不会显示新的攻击特效，也不会修改伤害、动作、判定、联机状态、存档或游戏 EFX 资源。

它用于记录游戏实际如何创建片手剑攻击效果，解决“片手专属目录中的少量 EFX 并不覆盖普通攻击”的映射问题。

## 系统和前置要求

- Steam 版《怪物猎人：崛起：曙光》16.0.2.0。
- 已正确安装 [REFramework](https://github.com/praydog/REFramework)。
- 游戏目录中应存在 `MonsterHunterRise.exe`、`dinput8.dll` 和 `reframework` 文件夹。

不需要指定防具、外观装备或片手剑皮肤；不需要 FirstNatives。

## 推荐安装方式

1. 完全退出游戏。
2. 下载并解压 `Lihuo-SnS-Action-Probe-0.4.0-diagnostic.zip`。
3. 将解压得到的 `reframework` 文件夹复制到游戏根目录。
4. Windows 询问时选择合并文件夹；本包不会覆盖 REFramework 的 DLL。
5. 启动游戏，装备任意片手剑，进入训练场完成普通连段和虫技。

Steam 默认游戏根目录通常是：

```text
C:\Program Files (x86)\Steam\steamapps\common\MonsterHunterRise
```

如果 Steam 库装在其他磁盘，请在 Steam 中右键游戏，依次选择“管理 → 浏览本地文件”，以打开的 `MonsterHunterRise.exe` 所在文件夹为准。

## 手动安装：逐文件复制到哪里

把压缩包中的文件复制成下面的最终结构：

```text
<游戏根目录>\
├─ MonsterHunterRise.exe
└─ reframework\
   └─ autorun\
      ├─ LihuoSnSVfxRuntimeProbe.lua
      ├─ LihuoSnSVfxRequestProbe.lua
      └─ LihuoSnSVfx\
         ├─ runtime_probe.lua
         └─ effect_request_probe.lua
```

不要额外套一层压缩包名称目录。错误示例：

```text
<游戏根目录>\Lihuo-SnS-Action-Probe-0.4.0-diagnostic\reframework\...
```

## Nexus Mods / Mod 管理器准备

压缩包以 `reframework/autorun` 为根，适合未来作为 Nexus Mods 的手动下载包。使用支持《怪物猎人：崛起》的管理器时，应确认部署后的最终路径仍与上面的目录树完全一致；若管理器多套了一层目录，请改用手动安装。

当前诊断包不是 Fluffy Mod Manager 的纯 `natives` 资源 Mod，不要把它当作已经完成的视觉替换包验收。

## 如何确认诊断包已生效

进入训练场并使用片手剑攻击后，检查：

```text
<游戏根目录>\reframework\data\LihuoSnSVfx-runtime-probe.json
<游戏根目录>\reframework\data\LihuoSnSVfx-effect-requests.json
```

`runtime-probe.json` 应显示：

- `player_type` 为 `snow.player.ShortSword`；
- `weapon_type` 为 `8`；
- `status` 为正在观察片手动作；
- `events` 中出现动作迁移。

注意：诊断包“成功”的表现是生成报告，不是出现火焰特效。

## 卸载

完全退出游戏后，只删除以下四个项目：

```text
reframework\autorun\LihuoSnSVfxRuntimeProbe.lua
reframework\autorun\LihuoSnSVfxRequestProbe.lua
reframework\autorun\LihuoSnSVfx\runtime_probe.lua
reframework\autorun\LihuoSnSVfx\effect_request_probe.lua
```

可选删除两个报告文件：

```text
reframework\data\LihuoSnSVfx-runtime-probe.json
reframework\data\LihuoSnSVfx-effect-requests.json
```

不要删除整个 `reframework` 文件夹或 `dinput8.dll`，它们可能由其他 Mod 共用。

## 故障排查

- 没有报告：确认 REFramework 正常加载，并检查 `re2_framework_log.txt` 中的 `Lihuo SnS VFX` 错误。
- 报告一直等待玩家：进入存档并装备任意片手剑。
- 有动作但 `event_count` 为 0：说明该动作没有经过当前监听的 ObjectEffectManager 入口；这属于诊断结果，不代表安装失败。
- 游戏版本不同：停止使用并提交游戏版本、REFramework 版本、完整日志和两个 JSON 报告。
