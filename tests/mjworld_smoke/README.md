# Linux 固定工具链轻量 smoke

只运行 Linux x86_64、官方 Godot 4.7.2.NET / MuJoCo 3.16.0 的小型 MjWorld 夹具。不是 G1、多 G1、模型搬迁压力或 GUI 验收。已有扩展需要先按根 README 构建。

```bash
python3 scripts/ci/install_godot.py /absolute/path/to/tools/godot
export GODOT_BIN="/absolute/path/to/tools/godot/Godot_v4.7.2-stable_mono_linux_x86_64/Godot_v4.7.2-stable_mono_linux.x86_64"
OUT="/absolute/new/output" bash tests/mjworld_smoke/run.sh
```

入口兼容原有 `GODOT_BIN` / `OUT` 调用方式；OUT 必须不存在或为空。Python 需要 3.10+，系统需 timeout 之外的常规 Linux 进程支持（runner 自行管理超时与进程组）。不依赖安装 EditorPlugin，不使用整份 demo/G1 资产复制。

工具链由 `scripts/ci/toolchain.json` 固定：Godot 下载来自官方 godot-builds 发布，压缩包 SHA256/SHA512 与执行文件 SHA256 均核验。已安装 Godot 也必须匹配准确 binary 和版本；仅匹配 `4.7.2` 前缀不够。MuJoCo 官方压缩包由 CMake 固定 URL/SHA256 获取；runner 再核对随扩展的 `libmujoco.so.3.16.0` SHA256。godot-cpp 使用现有固定 API 目标，不扩大引擎兼容范围。自行重编译的 MuJoCo 不属于此官方二进制严格入口。

## 状态与日志

每次准备新的项目缓存，共享 SDK/XDG 保留；不是独立全冷环境稳定性证明。初始化沿用已有 frame-delay 缓解，不重试、不修引擎。

`results.json` 记录 verify/import/positive/negative/audit_tests 各阶段，以及命令、实际进程返回值、超时和扩展哈希。进程被信号终止时 Python 记录负信号，例如 SIGSEGV=-11（shell 通常表现为139）。

| 整体状态 / 入口退出码 | 含义 |
|---|---|
| passed / 0 | 每个阶段通过 |
| failed / 1 | 工具链、初始化、运行、日志或单元检查失败 |
| blocked / 3 | 初始化退出139或SIGSEGV；归类为已知初始化问题，后续 smoke 为 not_run |

139 的类别不是新的根因诊断：保留完整日志，不能推断每次 SIGSEGV 都是同一引擎缺陷。该问题在产品基线中非阻断且未修复；在自动化执行中，未跑的 smoke 不能显示成功。CI 收到非零退出仍失败，不通过 `|| true` 或缓存重试变绿。

正例必须实际 exit0、恰好一个 PASS，且没有 ERROR/SCRIPT ERROR/泄漏。错误长度 qpos 在另一个进程验证：模型 nq=1，拒绝三个值，原 qpos 不变；必须 exit0、恰好一条完整匹配的预期错误和一个符合约束的 JSON。额外错误、重复错误、泄漏、超时与崩溃均失败。检查不因 Python `-O` 被关闭。

日志包括 version.log、import.log、positive.log、negative.log、audit-tests.log；未执行阶段不伪造日志。工作流使用 always 上传结果与日志，排除临时项目和二进制。构建/下载阶段失败则保留该阶段已产生的证据，不称 smoke 通过。

仅运行审计器/编排单元测试，无 Godot 仿真：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/mjworld_smoke -p 'test_*.py'
```

## CI 范围

`.github/workflows/cmake-build.yml` 默认使用 ubuntu-22.04 x86_64，仅构建 debug 扩展并运行本入口。具体 runner 成功与否以该提交 Actions 结果为准，不由工作流声明推导发行版兼容性。未配置新 secrets，也未扩大 token 权限。

旧跨平台与 release 构建配置原样归档到 `docs/ci-history/cmake-build.pre-linux-baseline.yml`，不再自动触发；归档不表示 Windows/ARM/mobile 已受支持。原提交2d7ec745混合 smoke 的历史失败保持不变。
