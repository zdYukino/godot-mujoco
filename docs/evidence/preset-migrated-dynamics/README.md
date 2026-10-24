# 迁移live状态后的提交前动力学校验

修复aeae2fd的原子性缺口：原实现只验证默认状态，rebuild已swap后才写preset controls/forward。现在rebuild在隔离combined候选完成live迁移、native body缓存姿态写入和整份controls，forward后检查qpos/qvel/qacc/qacc_smooth的mju_isBad范围、力/激活有限性和新增warning，再swap。提交后不重复进行未验证forward。拒绝时调用方还原spec/initial/dirty，活动model/data及revision未改变。

新增slide范围±3/live暂停qpos2/无force限幅回归：ctrl0、kp1e308产生非有限动力学；kp1e12产生有限但超过MuJoCo有效范围的qacc。均报告failed、无部分修改；另一实例、原PD/controls/qpos/revision/暂停时间/活动warning计数不变，随后step不报警不重置，安全kp30重试成功。不是强制编译器/分配失败注入，也不是用任意gain上限掩盖问题。

最终源码构建及以下入口全部exit0；正向日志无ERROR/SCRIPT ERROR/leak，数值回归无QACC warning：
- `cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2`
- `OUT=/workspace/shared/validation/preset-dynamics-final bash tests/runtime_presets/run.sh`：48项。
- `OUT=/workspace/shared/validation/preset-dynamics-final-native REPEAT=1 bash tests/native_backend/run.sh`：149项。
- `OUT=/workspace/shared/validation/preset-dynamics-final-typed bash tests/typed_control/run.sh`：69项。
- `OUT=/workspace/shared/validation/preset-dynamics-final-heightfield bash tests/heightfield/run.sh`：73项。

固定Linux Godot4.7.2.NET/MuJoCo3.16。native改变，dot必须独立重建；真实GUI未执行。PR5保持draft，不合main；既有冷导入/重负载/打包/Windows限制不变。只验证提交时状态，不承诺任意未来输入的全局数值稳定。
