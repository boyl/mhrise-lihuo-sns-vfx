# 增强运行时

当前只交付运行时诊断探针。它通过 `autorun` 根入口明确加载，并记录玩家、片手武器类型、动作状态迁移、玩家对象上的特效组件，以及片手自身 `ObjectEffectManager` 发出的特效容器和元素 ID。

基础报告输出到 `reframework/data/LihuoSnSVfx-runtime-probe.json`，特效请求报告输出到 `reframework/data/LihuoSnSVfx-effect-requests.json`。请求记录器只观察目标玩家的原生调用，不修改调用参数或返回值。

直接构造 `via.effect.ProviderData` 的单次派发探针仅用于确认引擎边界。实机证明空实例没有游戏初始化过的资源槽，`setResources(0, holder)` 会抛出引擎异常，因此正式实现不得继续依赖这条路径。

只有 Core 的动作映射和视觉层次通过实机验收后，才会增加最小特效派发器。增强版必须在换装、进出任务、猫车、返回村庄、脚本重载和退出时清理实例与缓存。
