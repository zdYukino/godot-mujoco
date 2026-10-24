# Pin/Hinge 演示输入修复

SceneTree不接收Node的_input回调。两个gui.gd现在创建DemoInput Node，由真实Node输入回调转发到演示handler。保留最近步进结果，避免UI取走完成结果后测试误判为空。

两入口run.sh新增input-smoke，通过Viewport.push_input发送实际键盘事件，不直接调用handler。各11/11通过，覆盖P暂停恢复、echo/release忽略、S精确.01s与pending重复、C重复删除、R重复重加、W保存并实例化。Pin49+21与Hinge44+19原测试也退出0，正常日志无ERROR/SCRIPT ERROR/leak，负例保持独立检查。

仅脚本/测试变更，未重建或修改native，仍SHA25644bf6f2675b83f91fc2cb911b017981c8ca41805aea3b7f1009f2922c7b5f5a0。headless事件派发不替代桌面键盘验收。完整日志 /workspace/shared/validation/demo-input-fix2；首次测试因GUI先取走完成结果出现1断言失败，原记录保留于demo-input-fix，不覆盖失败。
