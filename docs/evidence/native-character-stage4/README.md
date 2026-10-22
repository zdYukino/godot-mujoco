# Character stage 4 验收

Linux Godot 4.7.2.NET / MuJoCo 3.16，源码构建 exit 0（build.log）。
最终 body-motion 构建 `/workspace/shared/motion-build-8.log`；独立分支基于 c64164c。

- `motion.json`：RID 43 + Character 23，各三轮，全部通过。`checks.log` 保留首轮逐项断言，`executions.tsv` 保留退出码。
- `negative.json`：10/0，unsupported moving shape、scaled transform、不可行两墙恢复、不可表示擦边、float 路径越过薄墙；严格预期警告白名单。
- `presets.json`：51/0，包含 dirty kinematic 位姿穿过控制预设验证重建的 mocap 迁移回归。
- `precision.json`：864×3；`capsule.json`：150×3 + 14 负例。
- `cross-checks.log`：sweep 76×3 + 4 拒绝 + 一个独立认证的大坐标宽区间；overlap154×3、witness325。
- `semantics.json` 98，`contacts.json` 68，`area.json` 53+FIFO22；各自预期拒绝照原脚本严格核验。
- `numerics.log`：独立 sweep1048、capsule445 数值断言通过。

最终 motion 正/负例基于 build8，二进制 SHA256 见 motion.json。
预设与交叉回归基于 build6（SHA256 ded2c3e5275631dcc52aa2619250b7c870bded52da6c0f37e51614261e23ba2e）；
build7/8 后续只修改 body-motion 返回位移/实际路径认证，未改这些公共 query、server、sweep 几何实现。
所有最终运行脚本检查 ERROR/leak；正例也不允许 unsupported。未跑 sanitizer、Windows、打包、G1 heavy 或远端 CI。

真实失败及修复（未计为通过）：

1. motion-negative-1 的两墙恢复 7/1，原逐个推离会换边逃出夹困。联合约束修复后 negative-2 8/0，最终扩展10/0。
2. 初期 motion-2/3 暴露近零 fraction 世界坐标舍入和微小恢复被 is_zero_approx 吞掉；已修复，最终多帧 Character 严格通过。
3. motion-sweep 原负例期待大坐标永远拒绝；新凸最小点认证返回 [0.40000000596046,0.60000002384186]。更新用独立连续/实际 float 两端 gap 验证，擦边与极薄案例仍拒绝。首次更新有 GDScript 类型推断错误（final），显式 Vector3 后 final2 全通过。
4. motion-final7 断言虽全通过，但 Character 出现一次非预期 rounded-path 拒绝，整体判失败。build8 保留有实际端点 witness 的新增碰撞，再回退安全位移；没有 witness 的越墙仍拒绝。最终无该警告。

完整日志保存在 `/workspace/shared/validation/motion-*`，没有把早期失败替换成成功记录。
支持边界、query-only kinematic 与集成改动见 ../../native-character-stage4.zh-CN.md。
