using Godot;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;

// Uses the native ClassDB/Variant boundary, requiring no generated MjWorld C# wrapper.
// In this fixed-base 29-hinge fixture, joint IDs are qpos/qvel offsets.
public partial class BindingTest : Node
{
    private const string AssetDir = "res://assets/robots/unitree_g1/g1_29dof_mode_18/";
    private const int JointCount = 29;
    private const int Steps = 4000;
    private const int StepChunk = 100;
    private const double Offset = 0.02;
    private const double Tolerance = 0.002;
    private Node _world = null!;
    private readonly int[] _jointIds = new int[JointCount];
    private readonly int[] _actuatorIds = new int[JointCount];
    private readonly double[] _baseQpos = new double[JointCount];
    private readonly double[] _baseCtrl = new double[JointCount];
    private readonly double[] _lower = new double[JointCount];
    private readonly double[] _upper = new double[JointCount];
    private double _maxError;
    private int _trials;
    private int _steps;

    private sealed class JointEntry
    {
        [JsonPropertyName("name")] public string Name { get; set; } = "";
        [JsonPropertyName("lower")] public double Lower { get; set; }
        [JsonPropertyName("upper")] public double Upper { get; set; }
    }

    public override void _Ready()
    {
        var timer = Stopwatch.StartNew();
        bool passed = false;
        string failure = "";
        try
        {
            RunTests();
            passed = true;
        }
        catch (Exception error)
        {
            failure = error.Message;
            GD.PushError("G1 CSHARP: " + error);
        }
        GD.Print("G1_BINDING_RESULT " + JsonSerializer.Serialize(new
        {
            binding = "csharp", passed, joint_count = JointCount, trials = _trials,
            steps = _steps, max_position_error_rad = _maxError,
            position_tolerance_rad = Tolerance, elapsed_ms = timer.ElapsedMilliseconds, failure,
        }));
        GD.Print("G1 CSHARP " + (passed ? "PASS" : "FAIL"));
        GetTree().Quit(passed ? 0 : 1);
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private void RunTests()
    {
        Check(ClassDB.ClassExists("MjWorld"), "MjWorld extension is not registered");
        _world = (Node)ClassDB.Instantiate("MjWorld");
        AddChild(_world);
        _world.Call("set_auto_step", false);
        string version = _world.Call("get_mujoco_version").AsString();
        Check(version == "3.16.0", "expected MuJoCo 3.16.0; got " + version);
        string modelPath = OS.GetEnvironment("G1_MODEL_PATH");
        if (string.IsNullOrEmpty(modelPath)) modelPath = AssetDir + "actuation-test.xml";
        Check(_world.Call("load_model", modelPath).AsBool(),
            "load_model failed: " + _world.Call("get_last_error").AsString());
        Check(_world.Call("is_ready").AsBool(), "model is not ready after loading");
        foreach (string dimension in new[] { "get_nq", "get_nv", "get_nu", "get_njnt" })
            Check(_world.Call(dimension).AsInt32() == JointCount, dimension + " must be 29");
        Check(Math.Abs(_world.Call("get_timestep").AsDouble() - 0.001) < 1e-12,
            "fixture timestep must be 0.001");
        string inventoryPath = OS.GetEnvironment("G1_INVENTORY_PATH");
        if (string.IsNullOrEmpty(inventoryPath))
            inventoryPath = modelPath.GetBaseDir().PathJoin("joint-inventory.json");
        JointEntry[] inventory = JsonSerializer.Deserialize<JointEntry[]>(
            FileAccess.GetFileAsString(inventoryPath)) ?? Array.Empty<JointEntry>();
        Check(inventory.Length == JointCount, "inventory must list 29 joints");
        var seenNames = new HashSet<string>(StringComparer.Ordinal);
        var seenJoints = new HashSet<int>();
        var seenActuators = new HashSet<int>();
        for (int index = 0; index < JointCount; ++index)
        {
            JointEntry entry = inventory[index];
            Check(!string.IsNullOrEmpty(entry.Name) && seenNames.Add(entry.Name),
                "missing/duplicate inventory joint " + entry.Name);
            Check(double.IsFinite(entry.Lower) && double.IsFinite(entry.Upper)
                && entry.Upper - entry.Lower > 0.06, "invalid limits for " + entry.Name);
            int joint = _world.Call("joint_id", entry.Name).AsInt32();
            string actuatorName = entry.Name + "_position";
            int actuator = _world.Call("actuator_id", actuatorName).AsInt32();
            Check(joint >= 0 && joint < JointCount && seenJoints.Add(joint),
                "missing/duplicate joint " + entry.Name);
            Check(actuator >= 0 && actuator < JointCount && seenActuators.Add(actuator),
                "missing/duplicate actuator " + actuatorName);
            Check(_world.Call("joint_name", joint).AsString() == entry.Name &&
                _world.Call("actuator_name", actuator).AsString() == actuatorName,
                "name round-trip failed for " + entry.Name);
            _jointIds[index] = joint;
            _actuatorIds[index] = actuator;
            double basePosition = Math.Clamp(0.0, entry.Lower + 0.03, entry.Upper - 0.03);
            _baseQpos[joint] = basePosition;
            _baseCtrl[actuator] = basePosition;
            _lower[joint] = entry.Lower;
            _upper[joint] = entry.Upper;
        }
        for (int entryIndex = 0; entryIndex < JointCount; ++entryIndex)
        {
            foreach (double sign in new[] { 1.0, -1.0 })
            {
                double[] targetQpos = (double[])_baseQpos.Clone();
                double[] targetCtrl = (double[])_baseCtrl.Clone();
                targetQpos[_jointIds[entryIndex]] += sign * Offset;
                targetCtrl[_actuatorIds[entryIndex]] += sign * Offset;
                string label = $"{inventory[entryIndex].Name} {sign * Offset:+0.00;-0.00} scalar";
                ResetTrial(label);
                int actuator = _actuatorIds[entryIndex];
                Check(_world.Call("set_ctrl", actuator, targetCtrl[actuator]).AsBool(),
                    label + ": scalar write failed");
                Check(Math.Abs(_world.Call("get_ctrl", actuator).AsDouble() - targetCtrl[actuator]) < 1e-12,
                    label + ": scalar read mismatch");
                Settle(targetQpos, targetCtrl, label);
            }
        }
        foreach (double sign in new[] { 1.0, -1.0 })
        {
            double[] targetQpos = (double[])_baseQpos.Clone();
            double[] targetCtrl = (double[])_baseCtrl.Clone();
            for (int entryIndex = 0; entryIndex < JointCount; ++entryIndex)
            {
                double delta = sign * Offset * (entryIndex % 2 == 0 ? 1 : -1);
                targetQpos[_jointIds[entryIndex]] += delta;
                targetCtrl[_actuatorIds[entryIndex]] += delta;
            }
            string label = $"combined alternating {sign:+0;-0} batch";
            ResetTrial(label);
            Check(_world.Call("set_ctrl_array", targetCtrl).AsBool(), label + ": batch write failed");
            Settle(targetQpos, targetCtrl, label);
        }
        Check(_trials == JointCount * 2 + 2, "not all bounded trials ran");
    }

    private void ResetTrial(string label)
    {
        _world.Call("reset");
        Check(_world.Call("set_qpos", _baseQpos).AsBool(), label + ": set_qpos failed");
        Check(_world.Call("set_qvel", new double[JointCount]).AsBool(), label + ": set_qvel failed");
        Check(_world.Call("set_ctrl_array", _baseCtrl).AsBool(), label + ": base batch controls failed");
        _world.Call("forward");
        Check(Math.Abs(_world.Call("get_time").AsDouble()) < 1e-12, label + ": reset did not reset clock");
        CheckState(label);
    }

    private void CheckControls(double[] expected, string label)
    {
        double[] actual = _world.Call("get_ctrl_array").AsFloat64Array();
        Check(actual.Length == JointCount, label + ": wrong control array size");
        for (int index = 0; index < JointCount; ++index)
            Check(double.IsFinite(actual[index]) && Math.Abs(actual[index] - expected[index]) < 1e-12,
                $"{label}: control mismatch at {index}");
    }

    private void CheckState(string label)
    {
        double[] qpos = _world.Call("get_qpos").AsFloat64Array();
        double[] qvel = _world.Call("get_qvel").AsFloat64Array();
        Check(qpos.Length == JointCount && qvel.Length == JointCount, label + ": wrong state dimensions");
        for (int index = 0; index < JointCount; ++index)
        {
            Check(double.IsFinite(qpos[index]) && double.IsFinite(qvel[index]),
                $"{label}: nonfinite state at {index}");
            Check(qpos[index] >= _lower[index] - 1e-6 && qpos[index] <= _upper[index] + 1e-6,
                $"{label}: joint {index} left its limits");
        }
        Check(double.IsFinite(_world.Call("get_time").AsDouble()), label + ": nonfinite clock");
        Check(!_world.Call("has_warnings").AsBool() && _world.Call("get_warnings").AsGodotDictionary().Count == 0,
            label + ": MuJoCo warnings: " + _world.Call("get_warnings"));
        Check(_world.Call("get_ncon").AsInt32() == 0, label + ": contact-free fixture produced contacts");
    }

    private void Settle(double[] targetQpos, double[] targetCtrl, string label)
    {
        CheckControls(targetCtrl, label);
        for (int completed = 0; completed < Steps; completed += StepChunk)
        {
            Check(_world.Call("step", StepChunk).AsBool(), label + ": step failed");
            _steps += StepChunk;
            CheckState(label);
        }
        _world.Call("forward");
        CheckState(label);
        CheckControls(targetCtrl, label);
        Check(Math.Abs(_world.Call("get_time").AsDouble() - Steps * _world.Call("get_timestep").AsDouble()) < 1e-8,
            label + ": simulated time mismatch");
        double[] actual = _world.Call("get_qpos").AsFloat64Array();
        for (int index = 0; index < JointCount; ++index)
        {
            double error = Math.Abs(actual[index] - targetQpos[index]);
            _maxError = Math.Max(_maxError, error);
            Check(error <= Tolerance, $"{label}: joint {index} error {error:F9} exceeds {Tolerance:F3}");
        }
        ++_trials;
    }
}
