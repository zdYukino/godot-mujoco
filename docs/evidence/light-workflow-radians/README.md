# 综合示例弧度单位修复

独立 dot 验收发现 ea9b5c2 的 fixture 未声明 compiler angle，MuJoCo 默认 degree，使 ±1 的关节范围实际成为 ±0.0174533 rad；原7项符号检查未发现该缺陷。旧证据保持原样，不再将旧通过解读为目标跟踪正确。

本次明确 compiler angle="radian"；run.sh 核对生成 portable 包的 compiler/range；C# 增加双实例 ±0.5 rad 正向和反向跟踪断言，每个误差须小于0.03 rad，避免符号正确但幅值被限位的问题。

命令：`source /workspace/shared/tools/env.sh; OUT=/workspace/shared/validation/light-workflow-radians bash examples/light_workflow/run.sh`。
导入、生成、C# build、runtime 全 exit0；9项运行检查及 packaged_radian_limits_verified 通过。日志无 ERROR/SCRIPT ERROR/leak。沿用 ea9b5c2 native，未重建或复跑 native 重负载。

本次真实 GUI 未运行，待 dot 只针对示例重新生成项目并复验幅值与重开。PR3保持draft，不合main；其余环境与已知冷导入限制不变。
