# 运行中的作者编辑

本地编辑器场景是唯一设计源。F5 期间修改 body/joint/geom、外观或碰撞参数，会立即暂停实际 MuJoCo 世界；后台 worker 验证模型并组合共享世界，候选 MJB 在物理边界提交。成功后手动继续。失败、取消或超时保留草稿、上次有效预览与暂停的活动物理，禁止用旧缓存继续。

稳定 UUID 用于迁移兼容关节状态和处理重命名；坐标系变化的子树回到作者初始状态。世界选项、精度元数据、依赖和编译上下文随版本校验，陈旧任务不能覆盖新编辑。

游戏按钮通过 `world.request_editor_design(command)` 请求编辑器执行同一个可撤销、可保存的作者操作。没有对应编辑器连接时返回 0。旧资源替换 API 和实时调试协议已移除。

`instance.set_control(name, value)` 修改运行控制。完整运行控制预设通过 `request_control_preset(preset, expected_revision)` 后台验证，等待 `edit_finished` 判定真实结果，详见[控制预设事务](runtime-presets.zh-CN.md)。

重置仿真恢复内存检查点并保留已提交的设计与运行时增删；重建环境恢复保存的场景。保存作者设计不会把倒伏后的仿真状态自动写成初始状态。
