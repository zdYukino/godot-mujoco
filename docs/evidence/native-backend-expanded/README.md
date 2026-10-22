# 后端扩展集成候选：最终轻量验证

开发基点2442976，集成 c64164c（含Capsule db40796）、Area环境e1ab6ca、Pin/Hinge1e361d5。Character原型未纳入。共享冲突保留环境采样失效+关节解绑、bodymode FIFO，Area负例同时匹配Capsule支持和环境模式拒绝；未覆盖其他并行工作。

## 本次实际结果

固定 Linux x86_64 / Godot4.7.2.NET / MuJoCo3.16.0。源码构建exit0；exits.tsv记录20套runner全部exit0，extra-exits.tsv记录Area补充及独立数值exit0。组合测试另有integration_cross/executions.tsv（import、supplemental均0）。

- sweep浮点认证864×3；Capsule150×3、14负向断言；Pin49+21、Hinge44+19。
- Area环境85+补充38；组合22（Capsule Area→Capsule刚体重力/阻尼、场力驱动被动Hinge、clear/readd/delete）。
- Area监测53+FIFO22；contact68；P098+31；overlap154×3；witness325；sweep76×3+5拒绝；native149；cylinder35+9负例。
- heightfield73；clock118+C#；runtime presets48；typed control69；typed terrain50；editor160；严格core smoke。
- 纯数值sweep1048、capsule445。

正向日志无非预期ERROR/SCRIPT ERROR/leak；各负例入口独立核对预期拒绝，不能把负例错误混入正例。历史证据目录保留，其计数不叠加成本次结果。本目录归档runner日志、结果JSON、关键新增功能原始日志；全部原始日志另保留于 /workspace/shared/validation/backend-expanded，项目缓存与二进制不入库。

## 复跑

```sh
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2
# exits.tsv中每个suite，OUT必须是新的绝对目录
OUT=<fresh> REPEAT=1 bash tests/<suite>/run.sh
OUT=<fresh> bash tests/native_area_environment/run_supplemental.sh
OUT=<fresh> bash tests/native_backend_integration_cross/run.sh
g++ -std=c++17 -O2 tests/native_sweep/numerics.cpp -o /tmp/sweep-numerics
/tmp/sweep-numerics
g++ -std=c++17 -O2 tests/native_sweep/capsule_numerics.cpp -o /tmp/capsule-numerics
/tmp/capsule-numerics
```

## 验收边界

这是开发侧轻量通过，不是最终dot验收。2442976独立出现的17emptycasts不能由旧自动检查掩盖；本次浮点认证864×3包含最小复现的扩展检查，原独立probe和真实GUI仍需dot按新SHA重建复验。Area环境、Capsule和Pin/Hinge桌面交互也待dot；headless GUI smoke不替代真实GUI。

Pin/Hinge仅无环图固定软响应，Hinge限位/motor未实现且明确拒绝；额外锚点1米是柔度契约的一部分。接触冲量只含最后实际子步。Overlap/扫掠不返回导入MJCF对象，heightfield overlap不支持；扫掠只支持声明矩阵和平移，不是全形状/全尺度精确查询或CCD。Character未实现，Area空间查询仍未支持。

冷导入139未根治，沿用已有初始化缓解，不称全冷通过；未运行G1/多G1/模型迁移重负载、Windows、打包或远端CI。main未改。
