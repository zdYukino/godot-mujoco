using Godot;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using GDictionary = Godot.Collections.Dictionary;

namespace GodotMuJoCo;

public sealed record Access<T>(bool Success, T Value, string Error)
{
    internal static Access<T> Ok(T value) => new(true, value, "");
    internal static Access<T> Fail(string error) => new(false, default!, error);
}
public sealed record Operation(bool Success, string Error);
public sealed record WorldState(double Time, double Timestep, bool Paused, bool HasSnapshot,
    int Contacts, long PendingRequest, string LastError);
public sealed record JointState(IReadOnlyList<double> Position, IReadOnlyList<double> Velocity);
public sealed record BodyState(double Mass, Transform3D Transform);
public sealed record InstanceState(string Identity, long Revision, long PendingRequest,
    IReadOnlyDictionary<string, JointState> Joints, IReadOnlyDictionary<string, double> Controls,
    IReadOnlyDictionary<string, BodyState> Bodies);
public sealed record Completion(long RequestId, bool Success, string Error, long? Revision,
    double? Time, bool? Paused);
/// <summary>Accepted means queued, never completed. Await Finished for the actual outcome.</summary>
public sealed record Request(bool Accepted, long RequestId, string Error, Task<Completion> Finished)
{
    internal static Request Rejected(string error) => new(false, 0, error,
        Task.FromResult(new Completion(0, false, error, null, null, null)));
}

/// <summary>Saved design resource, separate from an instance's simulation state.</summary>
public sealed class ModelDesign
{
    internal Resource Native { get; }
    private ModelDesign(Resource resource) => Native = resource;
    public static Access<ModelDesign> Load(string path)
    {
        if (OS.GetThreadCallerId() != OS.GetMainThreadId())
            return Access<ModelDesign>.Fail("Load designs on the Godot main thread");
        if (string.IsNullOrWhiteSpace(path) || !FileAccess.FileExists(path)) return Access<ModelDesign>.Fail("Saved design does not exist");
        var resource = ResourceLoader.Load<Resource>(path, cacheMode: ResourceLoader.CacheMode.Ignore);
        if (resource == null || !resource.HasMethod("validate_package"))
            return Access<ModelDesign>.Fail("Expected a saved MjModelResource");
        string error = resource.Call("validate_package").AsString();
        return error.Length == 0 ? Access<ModelDesign>.Ok(new ModelDesign(resource)) : Access<ModelDesign>.Fail(error);
    }
}

/// <summary>Main-thread-only, disposable binding to one live node lifetime. Rebind after rebuilding.</summary>
public abstract class RuntimeHandle : IDisposable
{
    protected readonly Node Node;
    private readonly SceneTree tree;
    private readonly int thread = System.Environment.CurrentManagedThreadId;
    private readonly Callable completed;
    private readonly StringName signal;
    private TaskCompletionSource<Completion>? pending;
    private long requestId;
    private bool disposed;
    protected abstract bool SameLifetime { get; }
    protected abstract string PendingProperty { get; }

    protected RuntimeHandle(Node node, string completionSignal)
    {
        Node = node;
        tree = node.GetTree();
        signal = completionSignal;
        completed = Callable.From<GDictionary>(OnCompleted);
        node.Connect(signal, completed);
        node.TreeExiting += OnExit;
        tree.ProcessFrame += OnFrame;
    }
    protected static bool IsScript(Node node, string filename)
    {
        if (OS.GetThreadCallerId() != OS.GetMainThreadId() || !GodotObject.IsInstanceValid(node)
            || node.IsQueuedForDeletion() || !node.IsInsideTree()) return false;
        for (var script = node.GetScript().AsGodotObject() as Script;
             script != null; script = script.GetBaseScript())
            if (script.ResourcePath == "res://addons/godot_mujoco/model/" + filename) return true;
        return false;
    }
    public bool IsAlive => System.Environment.CurrentManagedThreadId == thread && !disposed
        && GodotObject.IsInstanceValid(Node) && !Node.IsQueuedForDeletion() && Node.IsInsideTree() && SameLifetime;
    protected string Unavailable => System.Environment.CurrentManagedThreadId != thread
        ? "MuJoCo handles must be used on the Godot main thread" : "Stale or disposed MuJoCo handle; bind the new live node";
    private void OnFrame() { if (!IsAlive) Dispose(); }
    private void OnExit() => Dispose();
    private void OnCompleted(GDictionary data)
    {
        if (pending == null || data["request"].AsInt64() != requestId) return;
        var completion = new Completion(requestId, data["success"].AsBool(), data["error"].AsString(),
            data.ContainsKey("revision") ? data["revision"].AsInt64() : null,
            data.ContainsKey("time") ? data["time"].AsDouble() : null,
            data.ContainsKey("paused") ? data["paused"].AsBool() : null);
        var source = pending; pending = null; requestId = 0;
        source.SetResult(completion);
    }
    protected Request Queue(string method, params Variant[] args)
    {
        if (!IsAlive) return Request.Rejected(Unavailable);
        if (pending != null || Node.Get(PendingProperty).AsInt64() != 0)
            return Request.Rejected("Wait for the pending request, including the initial snapshot");
        if (!Node.Call(method, args).AsBool()) return Request.Rejected(Node.Get("last_error").AsString());
        requestId = Node.Get(PendingProperty).AsInt64();
        pending = new TaskCompletionSource<Completion>();
        return new Request(true, requestId, "", pending.Task);
    }
    public void Dispose()
    {
        if (System.Environment.CurrentManagedThreadId != thread)
            throw new InvalidOperationException("Dispose on the Godot main thread");
        if (disposed) return;
        disposed = true;
        if (GodotObject.IsInstanceValid(tree)) tree.ProcessFrame -= OnFrame;
        if (GodotObject.IsInstanceValid(Node))
        {
            Node.TreeExiting -= OnExit;
            if (Node.IsConnected(signal, completed)) Node.Disconnect(signal, completed);
        }
        var source = pending; pending = null;
        source?.TrySetResult(new Completion(requestId, false,
            "Handle lifetime ended before completion was observed; this does not cancel an accepted native request",
            null, null, null));
        requestId = 0;
    }
    protected static IReadOnlyList<double> Numbers(Variant value)
    {
        // Native state uses PackedFloat64Array; snapshots are copied, never live native storage.
        return Array.AsReadOnly(value.AsFloat64Array());
    }
}

public sealed class WorldHandle : RuntimeHandle
{
    private readonly Rid space;
    protected override string PendingProperty => "command_request";
    protected override bool SameLifetime => Node.Get("ready_for_models").AsBool() && Node.Get("space").AsRid() == space;
    private WorldHandle(Node node) : base(node, "command_finished") => space = node.Get("space").AsRid();
    public static Access<WorldHandle> Bind(Node node)
    {
        if (!IsScript(node, "runtime_world.gd") || !node.Get("ready_for_models").AsBool())
            return Access<WorldHandle>.Fail("Expected a configured live MjRuntimeWorld");
        return Access<WorldHandle>.Ok(new WorldHandle(node));
    }
    public Access<WorldState> Read()
    {
        if (!IsAlive) return Access<WorldState>.Fail(Unavailable);
        var data = Node.Call("info").AsGodotDictionary();
        return Access<WorldState>.Ok(new WorldState(data["time"].AsDouble(), data["timestep"].AsDouble(),
            data["paused"].AsBool(), data["has_checkpoint"].AsBool(), data["ncon"].AsInt32(),
            Node.Get(PendingProperty).AsInt64(), Node.Get("last_error").AsString()));
    }
    public Request Pause(bool paused = true) => Queue("request_pause", paused);
    public Request Step(int count = 1) => Queue("step_simulation", count);
    public Request Capture() => Queue("capture_snapshot");
    public Request Reset() => Queue("reset_simulation");
}

public sealed class InstanceHandle : RuntimeHandle
{
    private readonly Rid rid;
    private readonly string identity;
    protected override string PendingProperty => "edit_request";
    protected override bool SameLifetime => Node.Get("model_rid").AsRid() == rid && rid.IsValid
        && Node.Get("live_id").AsString() == identity;
    private InstanceHandle(Node node) : base(node, "edit_finished")
    { rid = node.Get("model_rid").AsRid(); identity = node.Get("live_id").AsString(); }
    public static Access<InstanceHandle> Bind(Node node)
    {
        if (!IsScript(node, "model_instance.gd") || !node.Get("model_rid").AsRid().IsValid)
            return Access<InstanceHandle>.Fail("Expected a loaded live MjModelInstance");
        return Access<InstanceHandle>.Ok(new InstanceHandle(node));
    }
    public Access<InstanceState> Read()
    {
        if (!IsAlive) return Access<InstanceState>.Fail(Unavailable);
        var data = Node.Call("state").AsGodotDictionary();
        var joints = new Dictionary<string, JointState>();
        foreach (var entry in data["joints"].AsGodotDictionary())
        {
            var joint = entry.Value.AsGodotDictionary();
            joints.Add(entry.Key.AsString(), new JointState(Numbers(joint["qpos"]), Numbers(joint["qvel"])));
        }
        var controls = new Dictionary<string, double>();
        foreach (var entry in data["controls"].AsGodotDictionary()) controls.Add(entry.Key.AsString(), entry.Value.AsDouble());
        var bodies = new Dictionary<string, BodyState>();
        foreach (var entry in data["bodies"].AsGodotDictionary())
        {
            var body = entry.Value.AsGodotDictionary();
            bodies.Add(entry.Key.AsString(), new BodyState(body["mass"].AsDouble(), body["transform"].AsTransform3D()));
        }
        return Access<InstanceState>.Ok(new InstanceState(identity, data["property_revision"].AsInt64(),
            Node.Get(PendingProperty).AsInt64(), new ReadOnlyDictionary<string,JointState>(joints),
            new ReadOnlyDictionary<string,double>(controls), new ReadOnlyDictionary<string,BodyState>(bodies)));
    }
    public Operation SetControl(string actuator, double value)
    {
        var state = Read();
        if (!state.Success) return new Operation(false, state.Error);
        if (!double.IsFinite(value) || !state.Value.Controls.ContainsKey(actuator))
            return new Operation(false, "Unknown actuator or non-finite control");
        return Node.Call("set_control", actuator, value).AsBool()
            ? new Operation(true, "") : new Operation(false, "Control rejected by the runtime");
    }
    public Request Apply(ModelDesign design, long expectedRevision = -1)
    {
        if (design == null) return Request.Rejected("Choose a saved design");
        return Queue("request_model_edit", design.Native, expectedRevision);
    }
}
