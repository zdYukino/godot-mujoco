using Godot;
using System;
using System.Threading.Tasks;
using GodotMuJoCo;
using GDictionary = Godot.Collections.Dictionary;
public partial class ClockBinding : Node
{
    private async Task Complete(Node world) {
        for (int i=0; i<120 && world.Get("command_request").AsInt64()!=0; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        if (world.Get("command_request").AsInt64()!=0 || world.Get("last_error").AsString()!="")
            throw new Exception("C# simulation command failed: "+world.Get("last_error"));
    }
    private async Task<Completion> CompleteUi(Request request) {
        if (!request.Accepted) throw new Exception("Typed Extras request rejected: "+request.Error);
        for (int i=0; i<180 && !request.Finished.IsCompleted; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        if (!request.Finished.IsCompleted) throw new Exception("Typed Extras request timed out");
        return await request.Finished;
    }
    private async Task CheckExtras(Node world) {
        var extras=(Node)GD.Load<GDScript>("res://addons/godot_mujoco/viewer/godot_extras.gd").New().AsGodotObject();
        extras.Set("world",world);extras.Set("restore_preferences",false);AddChild(extras);
        for (int i=0; i<180 && extras.Get("status").AsString()!="ACTIVE"; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        if (extras.Get("status").AsString()!="ACTIVE") throw new Exception("Extras-only binding failed");
        if (ViewerHandle.Bind(extras).Success || ExtrasHandle.Bind(world).Success)
            throw new Exception("Typed UI handles accepted the wrong component role");
        var access=ExtrasHandle.Bind(extras);
        if (!access.Success) throw new Exception(access.Error);
        using var handle=access.Value;
        double before=Time(world);
        if (!(await CompleteUi(handle.CaptureSnapshot())).Success) throw new Exception("Extras capture failed");
        if (!(await CompleteUi(handle.Execute("step",new GDictionary{{"count",4}}))).Success
            || Math.Abs(Time(world)-before-.008)>1e-10) throw new Exception("Extras-only exact steps failed");
        if (!(await CompleteUi(handle.RestoreSnapshot())).Success || Math.Abs(Time(world)-before)>1e-10)
            throw new Exception("Extras snapshot restore failed");
        if (handle.Execute("help").Accepted) throw new Exception("Extras accepted original-only action");
        if (!handle.ShowExtras(true).Success || !handle.ShowExtras(false).Success || !handle.ShowPerformance(false).Success)
            throw new Exception("Typed Extras presentation API failed");
        var queued=handle.Execute("step",new GDictionary{{"count",2}});
        handle.SetEnabled(false);
        if ((await CompleteUi(queued)).Success || Math.Abs(Time(world)-before)>1e-10)
            throw new Exception("Typed Extras disable did not cancel queued steps");
        extras.QueueFree();await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        if (handle.IsAlive || handle.Read().Success) throw new Exception("Typed Extras handle survived removed component");
        GD.Print("CLOCK EXTRAS CSHARP PASS: independent role, exact steps, snapshot, UI, cancellation and disposal");
    }
    private double Time(Node world) => world.Call("info").AsGodotDictionary()["time"].AsDouble();
    public override async void _Ready() {
        try {
            var world=GD.Load<PackedScene>("res://Environment.tscn").Instantiate();
            world.Set("start_paused",true);AddChild(world);
            var deadline=Godot.Time.GetTicksMsec()+120000;
            while(!world.Get("author_started").AsBool()&&Godot.Time.GetTicksMsec()<deadline)
                await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);
            if(!world.Get("author_started").AsBool())throw new Exception("World compilation timeout");
            await Complete(world);
            if (!world.Call("step_simulation",7).AsBool()) throw new Exception("Step request rejected");
            await Complete(world);
            if (Math.Abs(Time(world)-.014)>1e-10) throw new Exception("Incorrect step time");
            if (!world.Call("reset_simulation").AsBool()) throw new Exception("Reset request rejected");
            await Complete(world);
            if (Time(world)!=0) throw new Exception("Reset time mismatch");
            if (!world.Call("request_pause",false).AsBool()) throw new Exception("Resume request rejected");
            await Complete(world);
            for (int i=0;i<5;i++) await ToSignal(GetTree(), SceneTree.SignalName.PhysicsFrame);
            world.Call("request_pause",true);await Complete(world);
            double paused=Time(world);
            for (int i=0;i<5;i++) await ToSignal(GetTree(), SceneTree.SignalName.PhysicsFrame);
            if (paused<=0 || Time(world)!=paused) throw new Exception("Pause/resume mismatch");
            await CheckExtras(world);
            world.QueueFree();await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
            GD.Print("CLOCK CSHARP PASS: saved environment, exact 7 steps, reset, resume, pause");
            GetTree().Quit(0);
        } catch(Exception e) { GD.PushError(e.ToString());GetTree().Quit(1); }
    }
}
