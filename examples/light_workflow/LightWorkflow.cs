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
            environment=GD.Load<PackedScene>("res://Environment.tscn").Instantiate<Node3D>();
            environment.GetNode("Floor").Free();AddChild(environment);
            world=WorldHandle.Bind(environment).Value;
            first=InstanceHandle.Bind(environment.GetNode("First")).Value;second=InstanceHandle.Bind(environment.GetNode("Second")).Value;
            for(int i=0;i<600&&world.Read().Value.PendingRequest!=0;i++)await Frames();
            if(world.Read().Value.PendingRequest!=0)throw new TimeoutException("Initial snapshot timeout");
            var design=TerrainDesign.Create(11,11,Enumerable.Repeat(.3f,121).ToArray()).Value;
            var created=TerrainHandle.Create(environment,"Terrain",design);
            if(!created.Success)throw new InvalidOperationException(created.Error);
            terrain=created.Value;await Finish(terrain.InitialRequest!);await Finish(world.Capture());
            var box=environment.GetNode<Node3D>("Box");box.AddChild(new MeshInstance3D{Mesh=new BoxMesh{Size=Vector3.One*.4f}});
            var camera=new Camera3D{Position=new Vector3(8,7,11),Current=true};AddChild(camera);camera.LookAt(new Vector3(1,0,0));
            AddChild(new DirectionalLight3D{RotationDegrees=new Vector3(-55,-25,0)});
            var canvas=new CanvasLayer();AddChild(canvas);var column=new VBoxContainer{Position=new Vector2(16,16)};canvas.AddChild(column);
            status=new Label();column.AddChild(status);
            var row=new HBoxContainer();column.AddChild(row);
            Button(row,"暂停 / 继续",()=>world.Pause(!world.Read().Value.Paused));
            Button(row,"精确步进 100",()=>world.Step(100));Button(row,"记录复位点",()=>world.Capture());
            Button(row,"重置仿真",()=>world.Reset());
            Button(row,"抬高地形角点",()=>{
                var state=terrain.Read().Value;var previous=state.CommittedDesign!;var values=previous.Heights.ToArray();values[0]+=.1f;
                return terrain.Update(TerrainDesign.Create(previous.Width,previous.Depth,values,previous.Pose,previous.Layer,previous.Mask).Value,state.Revision);
            });
            column.AddChild(new Label{Text="关节目标（弧度）：两个固定基座轻量模型反向控制；重置不撤销地形设计。"});
            control=new HSlider{MinValue=-.7,MaxValue=.7,Step=.05,CustomMinimumSize=new Vector2(500,24)};column.AddChild(control);
            control.ValueChanged+=value=>SetControl(value);
            busy=false;
            if(OS.GetCmdlineUserArgs().Contains("--self-test"))await SelfTest();
        }catch(Exception error){GD.PrintErr("LIGHT_WORKFLOW_FAIL ",error);GetTree().Quit(1);}
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
        Check(world!.Read().Value.Paused && terrain!.Read().Value.Active,"initialized paused composite world");
        SetControl(.5);await Finish(world.Step(100));
        Check(Math.Abs(world.Read().Value.Time-.2)<1e-9,"exact typed steps");
        Check(first!.Read().Value.Joints["hinge"].Position[0]>0&&second!.Read().Value.Joints["hinge"].Position[0]<0,"two controlled light robots");
        await Finish(world.Step(600));
        for(int i=0;i<3;i++)await ToSignal(GetTree(),SceneTree.SignalName.PhysicsFrame);
        Check(Math.Abs(environment.GetNode<Node3D>("Box").Position.Y-.5)<.04,"box contacts typed static terrain");
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
