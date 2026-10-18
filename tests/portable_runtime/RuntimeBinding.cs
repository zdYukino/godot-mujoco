using Godot;
using System;
public partial class RuntimeBinding : Node
{
    public override async void _Ready()
    {
        try {
            var world = GD.Load<PackedScene>("res://RuntimeScene.tscn").Instantiate<Node3D>();
            world.Set("start_paused", true);
            AddChild(world);
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
            var robot = world.GetNode<Node>("Model");
            var second = world.GetNode<Node>("SecondModel");
            if (!robot.Get("model_rid").AsRid().IsValid || !robot.Call("set_control", "left_elbow_joint_position", 0.7).AsBool())
                throw new Exception("C# load/control failed");
            var controls = robot.Call("state").AsGodotDictionary()["controls"].AsGodotDictionary();
            var other = second.Call("state").AsGodotDictionary()["controls"].AsGodotDictionary();
            if (Math.Abs(controls["left_elbow_joint_position"].AsDouble()-0.7)>1e-8 || Math.Abs(other["left_elbow_joint_position"].AsDouble()-0.4)>1e-8)
                throw new Exception("C# control state/isolation failed");
            world.Call("set_paused", false);
            for (int i=0;i<120;i++) await ToSignal(GetTree(), SceneTree.SignalName.PhysicsFrame);
            world.Call("set_paused", true);
            var joint = robot.Call("state").AsGodotDictionary()["joints"].AsGodotDictionary()["left_elbow_joint"].AsGodotDictionary();
            if (Math.Abs(joint["qpos"].AsGodotArray()[0].AsDouble()-0.7)>0.03) throw new Exception("C# drive did not reach target");
            world.Free();
            GD.Print("PORTABLE CSHARP PASS: saved scene, independent control, actual motion");
            GetTree().Quit(0);
        } catch (Exception e) { GD.PushError(e.ToString()); GetTree().Quit(1); }
    }
}
