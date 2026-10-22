对象阶段：`OUT=/workspace/shared/validation/scene-objects-02 bash tests/scene_objects/run.sh` exit0，18项通过，import/runtime无ERROR/SCRIPT ERROR/leak。native沿用ea9b5c2，无重构建。
首轮scene-objects-01因测试使用精确浮点比较出现3项失败，改用近似比较；原始失败记录仍在执行环境。真实GUI未执行，待dot独立验收。
