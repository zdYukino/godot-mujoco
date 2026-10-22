using Godot;
using GodotMuJoCo;
using System;
using System.Threading.Tasks;

public partial class TypedControl : Node
{
    private int checks;
    private void Check(bool condition, string name)
    { if (!condition) throw new Exception(name); checks++; GD.Print("PASS ", name); }
    private async Task Frames(int count = 1)
    { for (int i=0;i<count;i++) await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); }
    private async Task Idle(WorldHandle world)
    {
        for(int i=0;i<240;i++) { if(world.Read().Value.PendingRequest==0) return; await Frames(); }
        throw new Exception("initial command timeout");
    }
    private async Task<Completion> Done(Request request, bool success = true)
    {
        Check(request.Accepted,"request accepted separately from completion");
        for(int i=0;i<240 && !request.Finished.IsCompleted;i++) await Frames();
        Check(request.Finished.IsCompleted,"request completion bounded");
        var result=await request.Finished;
        Check(result.Success==success && result.RequestId==request.RequestId,"typed completion identity/outcome");
        return result;
    }
    public override async void _Ready()
    {
        try {
            var scene=GD.Load<PackedScene>("res://Environment.tscn");
            var host=new SubViewport { OwnWorld3D=true };AddChild(host);
            var node=scene.Instantiate<Node3D>();host.AddChild(node);
            using var world=WorldHandle.Bind(node).Value;
            using var first=InstanceHandle.Bind(node.GetNode<Node>("First")).Value;
            using var second=InstanceHandle.Bind(node.GetNode<Node>("Second")).Value;
            Check(!world.Step().Accepted,"initial snapshot pending rejects command");
            await Idle(world);
            Check(world.Read().Success && world.Read().Value.Paused,"typed world state");
            Check(await Task.Run(() => !world.Read().Success && !WorldHandle.Bind(node).Success && !ModelDesign.Load("res://missing.tres").Success),"worker thread access safely rejected");
            Check(first.Read().Value.Identity!=second.Read().Value.Identity,"distinct instance identities");
            Check(first.SetControl("drive",.6).Success && second.SetControl("drive",-.4).Success,"typed actuator control");
            Check(!first.SetControl("missing",1).Success && !first.SetControl("drive",double.NaN).Success,"invalid controls rejected without native error");
            Check(first.Read().Value.Controls["drive"]==.6 && second.Read().Value.Controls["drive"]==-.4,"controls isolated");
            var request=world.Step(100);
            Check(!request.Finished.IsCompleted && !world.Step().Accepted,"queued is not complete and duplicate rejected");
            await Done(request);
            Check(Math.Abs(world.Read().Value.Time-.2)<1e-9,"exact 100 steps");
            Check(first.Read().Value.Joints["hinge"].Position[0]>0 && second.Read().Value.Joints["hinge"].Position[0]<0,"two light joints move independently");
            await Frames(2);
            Check(node.GetNode<Node3D>("Box").Position.Y<2,"ordinary box shares simulation");
            var before=world.Read().Value.Time;
            var bad=await Done(world.Step(0),false);
            Check(bad.Error.Length>0 && world.Read().Value.Time==before,"boundary rejection distinguishes accepted from success");
            await Done(world.Capture());await Done(world.Step(5));await Done(world.Reset());
            Check(Math.Abs(world.Read().Value.Time-before)<1e-9,"typed snapshot reset");
            await Done(world.Pause(false));await Frames(4);await Done(world.Pause());
            Check(world.Read().Value.Time>before && world.Read().Value.Paused,"pause/resume feedback");
            var loaded=ModelDesign.Load(FileAccess.GetFileAsString("res://edited.txt").Trim());
            Check(loaded.Success,"load saved typed design");
            var firstBefore=first.Read().Value.Joints["hinge"].Position[0];
            var secondBefore=second.Read().Value.Joints["hinge"].Position[0];
            var edit=await Done(first.Apply(loaded.Value,0));
            Check(edit.Revision==1 && first.Read().Value.Revision==1 && second.Read().Value.Revision==0,"revision isolated");
            Check(Math.Abs(first.Read().Value.Joints["hinge"].Position[0]-firstBefore)<1e-10 && Math.Abs(second.Read().Value.Joints["hinge"].Position[0]-secondBefore)<1e-10,"compatible states continuous");
            Check(first.Read().Value.Bodies["arm"].Mass==2 && second.Read().Value.Bodies["arm"].Mass==1,"inertia revision applied to one instance");
            edit=await Done(first.Apply(loaded.Value,0),false);
            Check(edit.Error.Length>0 && first.Read().Value.Revision==1,"stale revision failure feedback");
            var firstNode=node.GetNode<Node>("First");
            firstNode.Call("unload_model");
            Check(!first.Read().Success && !first.SetControl("drive",.2).Success,"unloaded instance handle safely rejected immediately");
            Check(firstNode.Call("load_model").AsBool(),"same node reloaded");
            using var reloaded=InstanceHandle.Bind(firstNode).Value;
            Check(reloaded.IsAlive && !first.IsAlive,"old handle cannot bind a new RID implicitly");
            var pending=reloaded.Apply(loaded.Value);
            firstNode.QueueFree();
            Check(!reloaded.Read().Success,"queued deletion already rejected");
            await Frames(3);
            Check(pending.Finished.IsCompleted && !(await pending.Finished).Success,"deletion resolves outstanding completion");
            Check(second.SetControl("drive",.1).Success,"surviving instance still usable");
            host.QueueFree();await Frames(3);
            Check(!world.Read().Success && !world.Step().Accepted && !second.Read().Success,"freed world and model handles reject");
            host=new SubViewport { OwnWorld3D=true };AddChild(host);
            var next=scene.Instantiate<Node3D>();host.AddChild(next);
            using var reopened=WorldHandle.Bind(next).Value;
            using var model=InstanceHandle.Bind(next.GetNode<Node>("First")).Value;
            await Idle(reopened);
            Check(reopened.Read().Value.Time==0 && model.Read().Value.Controls["drive"]==0 && model.Read().Value.Revision==0,"saved environment reopens design not simulation");
            Check(model.Read().Value.Bodies["arm"].Mass==1 && !world.IsAlive,"rebuilt environment has original design and new handles");
            // Same node exits/re-enters: old handle must remain invalid after reentry.
            host.RemoveChild(next);host.AddChild(next);await Frames(3);
            Check(!reopened.IsAlive && !model.IsAlive,"same-node reentry cannot revive handles");
            using var rebound=WorldHandle.Bind(next).Value;
            Check(rebound.IsAlive,"explicit rebind after reentry");
            host.QueueFree();await Frames(3);
            GD.Print("TYPED_CONTROL_RESULT {\"passed\":",checks,",\"failed\":0}");GetTree().Quit();
        } catch(Exception error) { GD.PrintErr("TYPED_CONTROL_FAIL ",error);GetTree().Quit(1); }
    }
}
