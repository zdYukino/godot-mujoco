# 轻量 CI 远端状态诊断（2026-10-22）

诊断对象为 draft PR #1 的 `a4f8532b2b3fff788512346d8217a77e32420c59`。这是该 SHA 的观察记录，不代表后续提交的 CI 结果。[机器记录](evidence/linux-strict-smoke/remote-diagnosis-a4f8532.json)。

## 已确认

- PR 为 open/draft、可合并，head/base 正确；公开事件存在 opened 记录。
- 该 SHA 的 workflow runs、check runs、check suites、独立 commit statuses 均为0；仓库全部 workflow runs 也为0。combined status 的 pending 搭配空 statuses，不是排队证明。
- Actions 页面同样显示没有 run；workflow 列表标记 active。active 不能替代仓库/上层策略检查。
- 对 Actions permissions 的只读 API 查询返回 HTTP403 `Resource not accessible by integration`。该动作没有修改设置，也没有换凭据重试。
- actionlint 1.7.7 校验当前工作流 exit0（未集成 shellcheck，shell 内容另用 bash -n）；push 包含准确分支，pull_request 未过滤 opened，没有排除 draft 或 paths 条件。未发现解释零 run 的语法/事件条件错误。

因此当前分类是**未观察到触发，设置查询受限，原因未确认**；不是运行通过、不是已确认排队，也不能断言需要审批或平台故障。事件来源令牌限制、仓库/上层策略等仍不能用现有访问权限排除。

## 最小人工核对

1. 仓库拥有者打开 [Actions General 设置](https://github.com/zdYukino/godot-mujoco/settings/actions)，只核对当前 Actions 是否允许及是否显示策略限制，反馈页面提示；不要为诊断扩大 token 权限或新增 secrets。
2. 查看 [PR #1 Checks](https://github.com/zdYukino/godot-mujoco/pull/1/checks) / [Actions](https://github.com/zdYukino/godot-mujoco/actions)。仅当出现明确的审批按钮/原因时，按该提示处理；当前公开页面未证明存在审批请求。
3. 若拥有者确认 Actions 已允许、无审批提示，可在网页关闭再重新打开此 draft PR，以产生用户侧 reopened 事件；保持 draft、不要合并、不修改源码。然后核对产生的 run 的 head SHA；若仍为0，保留事件时间和设置提示交给维护者进一步诊断。

分支新增了 workflow_dispatch，但 main 的旧工作流没有它。GitHub 要求手动工作流存在于默认分支，故目前不能保证 Run workflow 按钮可用，也不建议为了显示按钮提前合并。依据：[官方手动运行说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)、[触发事件规则](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)。

## 工具链与构建复核

Godot mono 归档 SHA256 与官方 release asset digest 一致，SHA512 与同 release 的 SHA512-SUMS.txt 一致；执行文件哈希来自已校验归档，runner再次比对。MuJoCo 3.16.0 Linux x86_64 归档 SHA256 与官方 release asset digest 一致，CMake按该值下载校验，runner再核验运行库。来源链接见机器记录及 scripts/ci/toolchain.json。

.NET SDK 由官方 actions/setup-dotnet@v4 请求准确的8.0.426，已核实微软8.0发布元数据存在该版本。本项目未自行对 setup-dotnet 下载实施额外固定哈希，不能把 Godot mono 归档哈希称为 .NET SDK 哈希。

工作流在 checkout 后从源码执行 CMake configure/build，不下载预编译扩展，没有扩展构建缓存；MuJoCo使用官方运行库、godot-cpp在构建中获取编译。由于尚无远端 run，这只是已核对的执行配置，不是远端编译成功证明。

独立审查发现的版本进程失败证据缺口已修正：--version退出失败、超时或版本不符时，JSON仍保存实际argv/exit_code/timed_out；15项单元检查及本地轻量集成通过。证据见[修正复验](evidence/linux-strict-smoke/version-process-fix/)。没有修改产品源码、main、冻结基线、安全设置或凭据；没有运行重负载。
