# MjWorld 正例与负例隔离

`OUT=/absolute/new/output bash tests/mjworld_smoke/run.sh`。需要固定 Godot .NET 与已构建扩展，`GODOT_BIN` 可指定执行文件。

正例 HeadlessTest 必须 exit 0、恰好一个 PASS，且没有 ERROR 或泄漏。错误长度 qpos 在独立进程验证：模型 nq=1，拒绝三个值，原 qpos 不变；必须 exit 0、恰好一条完整匹配的预期错误和一个成功 JSON 结果。额外错误、重复错误、泄漏、超时与崩溃均失败。不对正例放宽日志审计。

每次复制到新的 project 并首次导入；导入失败立即停止。运行使用该次导入生成的缓存，不代表独立 XDG 冷导入稳定性证明。原提交 2d7ec745 的混合 smoke 仍记录为严格 FAIL，不能用本测试结果覆盖。
