# 素材来源与归属

## 天空

- 文件：`kloofendal_43d_clear_puresky_4k.hdr`
- 作品：Kloofendal 43d Clear Puresky
- 作者：Greg Zaal / Poly Haven
- 原作者下载：https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/kloofendal_43d_clear_puresky_4k.hdr
- 资产页面：https://polyhaven.com/a/kloofendal_43d_clear_puresky
- 许可：CC0，https://polyhaven.com/license （https://creativecommons.org/publicdomain/zero/1.0/）
- 原始大小：18,429,221 bytes
- SHA256：`1f92cbf17e46659ff37c9770d065280da226896b0f56091c4c1fca071da7fbeb`
- 格式：原始 Radiance HDR；仓库中未转换。Godot 运行导入时生成自己的纹理缓存，通过 PanoramaSkyMaterial 使用。
- Isaac Lab 引用同款 HDRI 的示例：https://github.com/isaac-sim/IsaacLab/blob/main/source/isaaclab_tasks/isaaclab_tasks/core/velocity/velocity_env_cfg.py

准确表述是“Isaac Lab 示例引用的同款原作者 HDRI”，并非将 NVIDIA 资产包的许可套用到此文件；从原作者直接获取的该资产适用 CC0。

## 形状与原创网格地板

`gallery.xml`、圆锥顶点/三角形及基础盒形地板由本项目 `generate_source.py` 原创生成，沿用仓库代码许可。圆锥没有来自外部模型库。当前地板无 NVIDIA 纹理、网格或 USD 数据。

NVIDIA Isaac Sim Flat Grid / default_environment.usd 未打包、未转换、未上传；其公开分发许可尚未确认。本项目采用用户选定的原创“纯色 + 固定间距线条”方案，参考常见 MuJoCo 地板风格，没有复制其具体原纹理。`floor_grid.gdshader` 为项目原创，沿用仓库代码许可。

## Godot 导入设置

随示例跟踪 `.hdr.import`：`compress/mode=0`、`compress/hdr_compression=0`、`detect_3d/compress_to=0`。禁用检测为 3D 后自动转 VRAM/BPTC 压缩，避免首次真实渲染触发昂贵的重压缩。原 HDR 字节、4K 分辨率和动态范围不变；代价是导入纹理缓存和显存占用高于块压缩版本（实际取决于渲染后端格式），并非零内存成本。`.godot` 生成缓存不随仓库提交。需要更小显存的用户可自行选择压缩，但应预留压缩时间和内存。
