# 轻量综合示例阶段

基于已合入 main 8157253，新功能分支 codex/light-workflow-native-cylinder。
执行：`source /workspace/shared/tools/env.sh; OUT=/workspace/shared/validation/light-workflow-02 bash examples/light_workflow/run.sh`。
导入、生成、C# build、运行均 exit 0；7 项通过，日志无 ERROR/SCRIPT ERROR/leak。
复用此前已验收 native 扩展，SHA256 d43e4fbb49b680f3ec7c5aca501e5c34ee9de6afb27587d8b86298f3fad5a1b9；本阶段不改 C++。
GUI 未在本环境执行，待 dot 依 examples/light_workflow/README.zh-CN.md 独立验收。冷导入139未修复；未执行重负载、Windows或打包。
