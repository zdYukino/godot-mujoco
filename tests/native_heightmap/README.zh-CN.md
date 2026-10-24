# 普通地形轻量回归与示例

说明、边界、Inspector 摩擦入口及 dot 图形步骤见 [普通 HeightMapShape3D](../../docs/native-heightmap.zh-CN.md)。

`GODOT_BIN=/path/to/fixed/godot OUT=/tmp/native-heightmap bash tests/native_heightmap/run.sh`

Main.tscn 为可在编辑器打开并 F6 的小球/地形示例；acceptance.gd 自动检查真实原生碰撞、资源更新、保存重开及接触摩擦。negative.gd 独立验证拒绝与有效状态保留。
