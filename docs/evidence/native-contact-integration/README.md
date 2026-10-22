# 接触报告集成验证

合并独立接触实现 fce6d0a 到 P0 a92cd39；冲突处理保留 P0 力/阻尼与回调语义，在最后实际 mj_step 后、mj_forward 前采样。补测先复现 deferred shape 删除后仍保留旧报告，以及偏心质心速度混淆，再修复并复测。

新增 contacts 68、semantics 98 + 31；并复跑 native149、cylinder35、clock118+C#、presets48、heightfield73、typed69。所有 runner 与源码构建 exit0；运行入口与 P0 相同，加 `OUT=<fresh> bash tests/native_contacts/run.sh`。负例各自隔离，contacts1 / semantics21 / cylinder9 条预期拒绝，不掩盖其他错误。

真实 GUI 未运行，headless gui-smoke 不能替代 dot 验收。报告的 contact impulse 仅最后子步，不是整帧累计。原分支历史证据仍保存在 ../native-contacts，本目录是集成后的新证据。
