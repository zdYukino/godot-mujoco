# Character 复审修复：三项 P2

基于 `37d202b4f295a8cb9d366090a414bfff09acb570`，独立追加提交；不改历史交付提交。

1. 大坐标恢复：独立 `probe.gd` 复现 sphere .5、from=(1e8,.4,0)、floor y=0、margin=.001、零运动。
   原版本无/有 local.x=-1e8 抵消均返回 travel.y=95.46843；修复后均为 .101001（目标 .101 + 1e-6 slop）。
   固定微小几何 slop，按每个 shape 实际 body/local 位移的法线投影认证恢复约束，无法表示则明确拒绝。
2. BODY unsafe：`unsafe_probe.gd` 复现 from.x=1e8、local.x=-1e8、motion.x=10、box center.x=6。
   原版本返回 hit=true、unsafe=.5，但实际 unsafe center=8 已超出 [5,7]。
   修复后明确警告拒绝、collision_count=0、travel=0；最终 BODY unsafe 需实际 witness，不允许 ideal-contact fallback。
   保留 wall=7.5 的可认证端点接触正例；不能因接触法线在穿透另一侧而漏掉已选定目标。
3. Kinematic 显式速度：共享 rest_result 为 kinematic 返回显式线速度加角速度的 COM 点速度。
   覆盖 body_test_motion、rest_info、旋转速度及偏置 shape COM。没有推断 transform 速度或扩展双向动力学。

验证环境 Linux Godot4.7.2.NET / MuJoCo3.16。source build exit0；最终二进制 SHA256：
`772c5a4df3638b2cc8106c2454dffd74aa06896a1538d1468e8cc7616d3835a0`。

- RID52 + Character23，各3轮，全部通过，无非预期 ERROR/leak/unsupported（motion.json / checks.log / executions.tsv）。
- 原负例全部保留，新增 wall=6 unsafe 拒绝：12/0，严格匹配7个预期警告（negative.json）。
- 同一源码构建交叉 overlap154×3、sweep76×3及既有负例/宽区间认证通过（cross-checks.log）。
- before.log / after.log 记录独立数值 probe；原始完整日志 `/workspace/shared/validation/recovery-direction-{before,after}`。
- 完整运行 `/workspace/shared/validation/motion-review2`、`motion-review-negative2`、`motion-review-overlap`、`motion-review-sweep`。

中间失败不隐去：motion-review 初版严格 unsafe witness 因过滤所有朝向运动方向的法线，漏掉大坐标端点另一侧接触；
近零 fraction 只搜索相邻 ULP，也有一次坡面警告。该运行判失败（RID49/2，Character断言23/0但警告不合格）。
后续保留选定目标的真实接触，并仅在已认证终点存在时细化 unsafe，motion-review2 全部通过。
没有放宽几何 gap、witness 或负例标准。未进行 Windows/打包/G1 heavy/远端CI。
