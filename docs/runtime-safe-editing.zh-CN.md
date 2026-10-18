# 运行中的安全模型编辑

编辑器预览、保存的设计资源和运行实例是三个不同对象。编辑字段不会隐式修改游戏中的机器人；保存资源也不会自动覆盖所有实例。

## 明确应用到目标

1. 在 MuJoCo 工作区编辑并 Apply，检查预览，再 Save project model。
2. 编辑器场景中可选中 MjModelInstance，点击 Assign saved model to scene selection；该操作可撤销，保存场景后重启才能读到新引用。
3. 游戏运行时，通过 runtime target 下拉选择准确实例。标识包含节点路径、instance id 和 RID 代次，不只依赖显示名称。
4. 点击 Apply saved model to runtime。pending 时重复点击被拒绝；完成后显示 property revision 或失败原因。失败后可修正并重试。

控制量通过 set_control 立即更新（当前主线程模式）；结构、质量/惯量等修改进入请求队列。实际流程是：请求快照→native 物理步安全边界→候选编译→检查世界 options 与同名状态兼容性→迁移→提交或回滚→保持原运行/暂停状态。UI 不直接修改正在 step 的 model/data。

同名 joint 必须保持类型/状态维度；同名 actuator 的动态类型与 activation 维度也必须兼容。新增对象使用保存的初始状态；删除对象从候选移除；其他兼容对象保留 time/qpos/qvel/act/ctrl。版本不匹配拒绝陈旧请求，实例卸载会取消未完成请求。

## GDScript

```gdscript
# candidate 必须是已经保存并通过依赖验证的 MjModelResource。
if robot.request_model_edit(candidate, robot.property_revision):
    var result: Dictionary = await robot.edit_finished
    if not result.success:
        status.text = result.error

robot.set_control("left_elbow_joint_position", 0.4)
```

参数与 actuator 名称必须来自实际模型。松弛自由 G1 没有合成 position actuator，不能照抄固定 G1 的控制名称。

## 与重置、保存的关系

状态重置保留当前已提交的模型设计，恢复内存快照中的兼容动态状态；它不撤销惯量/几何编辑。环境重建恢复保存的场景设计，显式丢弃运行时增删或未保存的场景改动。

运行中成功 Apply 不等于更新了场景资源引用。要让重新启动的游戏加载修改，必须显式 Assign 到编辑器场景节点并保存场景。运行快照不自动落盘；不要将倒伏后的仿真状态无提示地保存为设计。

同步编译可能暂停画面；本阶段不要求后台无停顿。模型参数错误、依赖损坏、候选不兼容都应留下错误与原运行对象。详见 [英文事务实现](runtime-safe-editing.md) 和 [验证报告](freebase-clock-validation.zh-CN.md)。
