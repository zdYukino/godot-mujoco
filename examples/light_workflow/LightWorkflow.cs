using Godot;
using GodotMuJoCo;
using System;
using System.Linq;
using System.Collections.Generic;
using System.Threading.Tasks;

public partial class LightWorkflow : Node
{
    private WorldHandle? world;
    private InstanceHandle? first,second;
    private TerrainHandle? terrain;
    private Node3D environment=null!;
    private Label status=null!;
    private HSlider control=null!;
    private readonly List<Button> buttons=new();
    private string message="初始化…";
    private bool busy=true;
    private async Task Frames(int n=1) {for(int i=0;i<n;i++)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);}
    private async Task<Completion> Finish(Request request) {
        if(!request.Accepted)throw new InvalidOperationException(request.Error);
        message=$"accepted request={request.RequestId}，等待完成";
        for(int i=0;i<600&&!request.Finished.IsCompleted;i++)await Frames();
        if(!request.Finished.IsCompleted)throw new TimeoutException("Request completion timeout");
        var result=await request.Finished;
        if(!result.Success)throw new InvalidOperationException(result.Error);
        message=$"completed request={result.RequestId}";return result;
    }
    private async Task Run(Func<Request> operation) {
        if(busy)return;busy=true;
        try{await Finish(operation());}catch(Exception error){message="失败："+error.Message;}
        finally{busy=false;}
    }
    private void Button(HBoxContainer row,string title,Func<Request> operation) {
        var button=new Button{Text=title};row.AddChild(button);buttons.Add(button);button.Pressed+=async()=>await Run(operation);
    }
    public override async void _Ready() {
        try {
            environment=GetNode<Node3D>("Environment");
            var deadline=Time.GetTicksMsec()+120000;
            while(!environment.Get("author_started").AsBool() && Time.GetTicksMsec()<deadline)await Frames();
            if(!environment.Get("author_started").AsBool())throw new TimeoutException("Initial world compilation timeout");
            world=WorldHandle.Bind(environment).Value;
            first=InstanceHandle.Bind(environment.GetNode("First")).Value;
            second=InstanceHandle.Bind(environment.GetNode("Second")).Value;
            terrain=TerrainHandle.Bind(environment.GetNode("Terrain")).Value;
            while(world.Read().Value.PendingRequest!=0)await Frames();
            var column=new VBoxContainer();
            status=new Label();column.AddChild(status);
            var viewer=environment.Get("runtime_viewer").AsGodotObject() as Node;
            if(viewer==null)throw new InvalidOperationException("RuntimeViewer unavailable");
            viewer.Call("register_extension","light_workflow","轻量模型驱动",column,
                "两个固定基座轻量模型反向控制。全局仿真操作使用原版 Simulation 面板；F11 仅为 Godot 附加功能，精确步进位于 Tools；关节目标仅改变运行控制，地形设计请在 Godot 编辑器修改。");
            viewer.Connect("world_changed",Callable.From<Node>(RebindWorld));
            column.AddChild(new Label{Text="关节目标（弧度）：两个固定基座轻量模型反向控制；重置不撤销地形设计。"});
            control=new HSlider{MinValue=-.7,MaxValue=.7,Step=.05,CustomMinimumSize=new Vector2(500,24)};column.AddChild(control);
            control.ValueChanged+=value=>SetControl(value);
            busy=false;
            if(OS.GetCmdlineUserArgs().Contains("--self-test"))await SelfTest();
        }catch(Exception error){GD.PrintErr("LIGHT_WORKFLOW_FAIL ",error);GetTree().Quit(1);}
    }
    private void RebindWorld(Node node) {
        world?.Dispose();first?.Dispose();second?.Dispose();terrain?.Dispose();
        environment=(Node3D)node;
        world=WorldHandle.Bind(environment).Value;
        first=InstanceHandle.Bind(environment.GetNode("First")).Value;
        second=InstanceHandle.Bind(environment.GetNode("Second")).Value;
        terrain=TerrainHandle.Bind(environment.GetNode("Terrain")).Value;
    }
    private void SetControl(double value) {
        var a=first!.SetControl("drive",value);var b=second!.SetControl("drive",-value);
        message=a.Success&&b.Success?"控制已更新":"控制拒绝："+a.Error+b.Error;
    }
    public override void _Process(double delta) {
        if(status==null||world==null)return;
        var state=world.Read();if(!state.Success)return;
        status.Text=$"time={state.Value.Time:F3}s paused={state.Value.Paused} contacts={state.Value.Contacts}\n{message}";
        foreach(var button in buttons)button.Disabled=busy;
        control.Editable=!busy;
        if(!busy && first!=null) { var snapshot=first.Read(); if(snapshot.Success)control.SetValueNoSignal(snapshot.Value.Controls["drive"]); }
    }
    private async Task SelfTest() {
        int checks=0;
        void Check(bool ok,string label){if(!ok)throw new Exception(label);checks++;GD.Print("PASS ",label);}
        if(DisplayServer.GetName()!="headless") {
            GetTree().Root.GrabFocus();DisplayServer.WindowSetVsyncMode(DisplayServer.VSyncMode.Disabled);
            if(ProjectSettings.GetSetting("rendering/mujoco_native_view/renderer",-1).AsInt32()==1) {
                var deadline=Time.GetTicksMsec()+30000;
                while(!environment.Get("native_view_active").AsBool()&&Time.GetTicksMsec()<deadline)await Frames();
                Check(environment.Get("native_view_active").AsBool(),"real native renderer active");
                var view=(Node)environment.Get("native_view").AsGodotObject();
                var render=view.Get("latest").AsGodotDictionary();
                Check(render["authoritative_scene"].AsBool()&&render["bridge_step_calls"].AsInt64()==0&&render["gl_errors"].AsInt64()==0,"native rendering does not add physics steps");
            }
        }
        Check(world!.Read().Value.Paused && terrain!.Read().Value.Active,"initialized paused composite world");
        SetControl(.5);await Finish(world.Step(100));
        Check(Math.Abs(world.Read().Value.Time-.2)<1e-9,"exact typed steps");
        Check(first!.Read().Value.Joints["hinge"].Position[0]>0&&second!.Read().Value.Joints["hinge"].Position[0]<0,"two controlled light robots");
        await Finish(world.Step(600));
        for(int i=0;i<3;i++)await ToSignal(GetTree(),SceneTree.SignalName.PhysicsFrame);
        Check(Math.Abs(environment.GetNode<Node3D>("Box").Position.Y-.5)<.04,"box contacts typed static terrain");
        Check(Math.Abs(first.Read().Value.Joints["hinge"].Position[0]-.5)<.03 &&
              Math.Abs(second!.Read().Value.Joints["hinge"].Position[0]+.5)<.03,
              "both joints track +/-0.5 radians beyond degree-sized limits");
        SetControl(-.5);await Finish(world.Step(700));
        Check(Math.Abs(first.Read().Value.Joints["hinge"].Position[0]+.5)<.03 &&
              Math.Abs(second.Read().Value.Joints["hinge"].Position[0]-.5)<.03,
              "both joints track reversed radian targets");
        await Finish(world.Reset());
        Check(world.Read().Value.Time==0&&first.Read().Value.Controls["drive"]==0,"reset restores checkpoint time and controls");
        await Finish(world.Pause(false));for(int i=0;i<3;i++)await ToSignal(GetTree(),SceneTree.SignalName.PhysicsFrame);
        await Finish(world.Pause());Check(world.Read().Value.Time>0&&world.Read().Value.Paused,"resume and pause completed");
        await Finish(world.Capture());double time=world.Read().Value.Time;await Finish(world.Step(10));await Finish(world.Reset());
        Check(Math.Abs(world.Read().Value.Time-time)<1e-10,"new checkpoint reset");
        control.SetValueNoSignal(0);GD.Print("LIGHT_WORKFLOW_RESULT {\"passed\":",checks,",\"failed\":0}");
        environment.QueueFree();await Frames(3);GetTree().Quit();
    }
    public override void _ExitTree(){terrain?.Dispose();first?.Dispose();second?.Dispose();world?.Dispose();}
}
