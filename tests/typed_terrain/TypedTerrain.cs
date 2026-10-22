using Godot;
using GodotMuJoCo;
using System;
using System.Linq;
using System.Threading.Tasks;
public partial class TypedTerrain : Node
{
    private int checks;
    private void Check(bool value,string label) { if(!value)throw new Exception(label);checks++;GD.Print("PASS ",label); }
    private async Task Frames(int count=1) { for(int i=0;i<count;i++)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame); }
    private async Task<Completion> Done(Request request,bool success=true) {
        Check(request.Accepted,"request accepted");
        for(int i=0;i<240&&!request.Finished.IsCompleted;i++)await Frames();
        Check(request.Finished.IsCompleted,"completion bounded");
        var result=await request.Finished;Check(result.Success==success && result.RequestId==request.RequestId,"actual completion result");return result;
    }
    public override async void _Ready() {
        try {
            var host=new SubViewport { OwnWorld3D=true };AddChild(host);
            var scene=GD.Load<PackedScene>("res://Environment.tscn");var node=scene.Instantiate<Node3D>();node.GetNode("Floor").Free();host.AddChild(node);
            using var world=WorldHandle.Bind(node).Value;
            using var modelA=InstanceHandle.Bind(node.GetNode("First")).Value;
            using var modelB=InstanceHandle.Bind(node.GetNode("Second")).Value;
            for(int i=0;i<240&&world.Read().Value.PendingRequest!=0;i++)await Frames();
            Check(!TerrainHandle.Bind(node).Success,"unrelated node rejected");
            var heights=Enumerable.Repeat(.3f,121).ToArray();
            var design=TerrainDesign.Create(11,11,heights).Value;heights[0]=99;
            Check(design.Heights[0]==.3f,"design copies caller data");
            Check(!TerrainDesign.Create(2,2,new[]{0f,float.NaN,0,0}).Success && !TerrainDesign.Create(1,2,new[]{0f,0}).Success,"invalid grid rejected");
            Check(!TerrainDesign.Create(2,2,new float[4],new Transform3D(Basis.Identity.Scaled(new Vector3(2,1,1)),Vector3.Zero)).Success,"scaled terrain design rejected");
            var pose=new Transform3D(Basis.Identity,new Vector3(20,0,0));
            var otherDesign=TerrainDesign.Create(11,11,Enumerable.Repeat(.6f,121).ToArray(),pose).Value;
            using var first=TerrainHandle.Create(node,"Ground",design).Value;
            using var second=TerrainHandle.Create(node,"OtherGround",otherDesign).Value;
            Check(first.InitialRequest!.Accepted && !first.InitialRequest.Finished.IsCompleted,"create queued not complete");
            Check(!first.Update(design,0).Accepted,"concurrent same instance rejected");
            using var alias=TerrainHandle.Bind(node.GetNode("Ground")).Value;
            Check(!alias.Update(design,0).Accepted,"second handle respects node pending gate");
            await Done(first.InitialRequest);await Done(second.InitialRequest!);
            Check(first.Read().Value.Identity!=second.Read().Value.Identity && first.Read().Value.Revision==1,"two terrain identities isolated");
            var firstNode=node.GetNode("Ground");
            Check(await Task.Run(()=>!first.Read().Success && !TerrainHandle.Bind(firstNode).Success),"worker access rejected");
            await Done(world.Step(700));
            for(int i=0;i<5;i++)await ToSignal(GetTree(),SceneTree.SignalName.PhysicsFrame);
            Check(Math.Abs(node.GetNode<Node3D>("Box").Position.Y-.5)<.04,"ordinary box contacts typed terrain");
            Check(Math.Abs(modelA.Read().Value.Bodies["arm"].Transform.Origin.Y-.4)<.04 && Math.Abs(modelB.Read().Value.Bodies["arm"].Transform.Origin.Y-.4)<.04,"two light models contact typed terrain");
            var qA=modelA.Read().Value.Joints["hinge"].Position[0];var qB=modelB.Read().Value.Joints["hinge"].Position[0];
            var target=TerrainDesign.Create(11,11,Enumerable.Repeat(.4f,121).ToArray()).Value;
            await Done(first.Update(target,0),false);
            Check(first.Read().Value.Revision==1 && first.Read().Value.CommittedDesign!.Heights[0]==.3f,"stale revision preserves geometry snapshot");
            firstNode.SetProcess(false);
            var update=first.Update(target,1);
            await ToSignal(GetTree(),SceneTree.SignalName.PhysicsFrame);await ToSignal(GetTree(),SceneTree.SignalName.PhysicsFrame);
            var committed=first.Read();
            Check(committed.Success && committed.Value.Revision==2 && update.Finished.IsCompleted,"read polls committed revision before idle callback");
            firstNode.SetProcess(true);await Done(update);
            Check(modelA.Read().Value.Joints["hinge"].Position[0]==qA && modelB.Read().Value.Joints["hinge"].Position[0]==qB,"terrain update preserves two model states");
            Check(first.Read().Value.Revision==2 && second.Read().Value.Revision==1 && second.Read().Value.CommittedDesign!.Heights[0]==.6f,"update isolated and revision coherent");
            var badResolution=TerrainDesign.Create(2,2,new float[4]).Value;
            await Done(first.Update(badResolution,2),false);
            Check(first.Read().Value.Revision==2 && first.Read().Value.Error.Length>0,"native failure retains revision and error");
            await Done(first.Remove());
            Check(!first.Read().Success && !first.Update(design,0).Accepted,"successful remove invalidates old handle");
            using var fresh=TerrainHandle.Bind(node.GetNode("Ground")).Value;
            await Done(fresh.Update(design,0));
            Check(fresh.Read().Value.Active && fresh.Read().Value.Revision==1,"explicit rebind adds new generation");
            var inherited=(Node3D)GD.Load<GDScript>("res://derived_terrain.gd").New().AsGodotObject();inherited.Name="Inherited";inherited.Set("auto_apply",false);node.AddChild(inherited);
            using var inheritedHandle=TerrainHandle.Bind(inherited).Value;
            Check(inheritedHandle.IsAlive,"inherited terrain bound");
            var pending=inheritedHandle.Update(design,0);inherited.QueueFree();
            Check(!inheritedHandle.Read().Success,"queued node deletion rejected");await Frames(3);
            Check(pending.Finished.IsCompleted && !(await pending.Finished).Success,"deletion settles pending observer");
            var ground=node.GetNode<Node3D>("Ground");node.RemoveChild(ground);node.AddChild(ground);await Frames(3);
            Check(!fresh.IsAlive,"same-node reentry invalidates old handle");
            using var rebound=TerrainHandle.Bind(ground).Value;
            for(int i=0;i<240 && rebound.Read().Value.PendingRequest!=0;i++)await Frames();
            Check(rebound.Read().Value.Active && rebound.Read().Value.Revision==1,"reentry auto-applies saved design with fresh revision");
            var packed=new PackedScene();Check(packed.Pack(ground)==Error.Ok && ResourceSaver.Save(packed,"res://TypedGround.tscn")==Error.Ok,"typed created node saves authored design");
            var saved=GD.Load<PackedScene>("res://TypedGround.tscn").Instantiate<Node3D>();saved.Name="Reopened";node.AddChild(saved);
            using var reopened=TerrainHandle.Bind(saved).Value;
            for(int i=0;i<240 && reopened.Read().Value.PendingRequest!=0;i++)await Frames();
            Check(reopened.Read().Value.Active && reopened.Read().Value.Revision==1 && reopened.Read().Value.CommittedDesign!.Heights[0]==.3f,"saved terrain reopens design without old runtime revision");
            host.QueueFree();await Frames(3);
            Check(!second.Read().Success && !rebound.Read().Success,"world destruction invalidates handles");
            GD.Print("TYPED_TERRAIN_RESULT {\"passed\":",checks,",\"failed\":0}");GetTree().Quit();
        } catch(Exception error) {GD.PrintErr("TYPED_TERRAIN_FAIL ",error);GetTree().Quit(1);}
    }
}
