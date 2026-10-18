using Godot;
using System;
using System.Threading.Tasks;
public partial class ClockBinding : Node
{
    private async Task Complete(Node world) {
        for (int i=0; i<120 && world.Get("command_request").AsInt64()!=0; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        if (world.Get("command_request").AsInt64()!=0 || world.Get("last_error").AsString()!="")
            throw new Exception("C# simulation command failed: "+world.Get("last_error"));
    }
    private double Time(Node world) => world.Call("info").AsGodotDictionary()["time"].AsDouble();
    public override async void _Ready() {
        try {
            var world=GD.Load<PackedScene>("res://Environment.tscn").Instantiate();
            world.Set("start_paused",true);AddChild(world);await Complete(world);
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
            world.QueueFree();await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
            GD.Print("CLOCK CSHARP PASS: saved environment, exact 7 steps, reset, resume, pause");
            GetTree().Quit(0);
        } catch(Exception e) { GD.PushError(e.ToString());GetTree().Quit(1); }
    }
}
