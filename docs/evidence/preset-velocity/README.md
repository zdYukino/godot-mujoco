# velocity-compatible 预设规范化修复

position-compatible 使用 kp=1 / kv=0，velocity-compatible 使用 kv=1，遵守原生 velocity kv>0 合法域。只改 GDScript，不修改或重建 native。

`source /workspace/shared/tools/env.sh; OUT=/workspace/shared/validation/preset-velocity-01 bash tests/control_presets/run.sh`：exit0，39项通过，import/runtime无ERROR/SCRIPT ERROR/leak。

新增9项覆盖标准joint velocity模型、无源修改的签名、编辑器保存/加载、无虚构kp、修改kv后的签名兼容、kv=0原子拒绝、独立导入不同初始kv模型后加载。原30项仍运行，保留axis/anchor及非joint拒绝验证。

其他对象/编辑器/地形回归沿用f53b03d证据，本次未重复；真实GUI待dot。PR4保持draft，不合main。
