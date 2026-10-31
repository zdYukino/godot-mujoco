using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using GDictionary = Godot.Collections.Dictionary;

namespace GodotMuJoCo;

/// <summary>Shared request lifetime for explicitly authored runtime UI components.</summary>
public abstract class RuntimeUiHandle : IDisposable
{
    private readonly Node component;
    private readonly SceneTree tree;
    private readonly int thread = System.Environment.CurrentManagedThreadId;
    private readonly Callable completed;
    private readonly Dictionary<long,TaskCompletionSource<Completion>> pending = new();
    private bool disposed;

    protected RuntimeUiHandle(Node node)
    {
        component = node;
        tree = node.GetTree();
        completed = Callable.From<long,GDictionary>(OnCompleted);
        component.Connect("action_finished", completed);
        component.TreeExiting += Dispose;
        tree.ProcessFrame += OnFrame;
    }

    protected static bool IsComponent(Node node, string scriptPath)
    {
        if (OS.GetThreadCallerId() != OS.GetMainThreadId() || !GodotObject.IsInstanceValid(node)
            || !node.IsInsideTree() || node.IsQueuedForDeletion()) return false;
        for (var script = node.GetScript().AsGodotObject() as Script; script != null; script = script.GetBaseScript())
            if (script.ResourcePath == scriptPath) return true;
        return false;
    }

    public bool IsAlive => thread == System.Environment.CurrentManagedThreadId && !disposed
        && GodotObject.IsInstanceValid(component) && component.IsInsideTree() && !component.IsQueuedForDeletion();
    private string Unavailable => thread != System.Environment.CurrentManagedThreadId
        ? "Use viewer handles on the Godot main thread" : "Viewer component was removed or its handle disposed";
    public Access<GDictionary> Read() => IsAlive
        ? Access<GDictionary>.Ok(component.Call("read_state").AsGodotDictionary().Duplicate(true))
        : Access<GDictionary>.Fail(Unavailable);

    public Request Execute(string actionId, GDictionary? arguments = null)
    {
        if (!IsAlive) return Request.Rejected(Unavailable);
        long id = component.Call("execute", actionId, arguments ?? new GDictionary()).AsInt64();
        if (id == 0) return Request.Rejected(component.Get("last_error").AsString());
        var source = new TaskCompletionSource<Completion>();
        pending.Add(id, source);
        Poll(id);
        return new Request(true, id, "", source.Task);
    }

    public Operation SetEnabled(bool enabled)
    {
        if (!IsAlive) return new Operation(false, Unavailable);
        component.Set("enabled", enabled);
        return new Operation(true, "");
    }
    protected Operation View(string method, params Variant[] values)
    {
        if (!IsAlive) return new Operation(false, Unavailable);
        if (!component.Get("enabled").AsBool()) return new Operation(false, "Viewer component is disabled");
        bool accepted = component.Call(method, values).AsBool();
        return new Operation(accepted, accepted ? "" : component.Get("last_error").AsString());
    }

    private void Poll(long id)
    {
        if (!pending.ContainsKey(id)) return;
        var result = component.Call("action_result", id).AsGodotDictionary();
        if (result.Count > 0) OnCompleted(id, result);
    }
    private void OnFrame()
    {
        if (!IsAlive) { Dispose(); return; }
        foreach (long id in new List<long>(pending.Keys)) Poll(id);
    }
    private void OnCompleted(long id, GDictionary result)
    {
        if (!pending.Remove(id, out var source)) return;
        source.TrySetResult(new Completion(id, result.ContainsKey("success") && result["success"].AsBool(),
            result.ContainsKey("error") ? result["error"].AsString() : "",
            result.ContainsKey("revision") ? result["revision"].AsInt64() : null,
            result.ContainsKey("time") ? result["time"].AsDouble() : null,
            result.ContainsKey("paused") ? result["paused"].AsBool() : null));
    }
    public void Dispose()
    {
        if (thread != System.Environment.CurrentManagedThreadId)
            throw new InvalidOperationException("Dispose viewer handles on the Godot main thread");
        if (disposed) return;
        disposed = true;
        if (GodotObject.IsInstanceValid(tree)) tree.ProcessFrame -= OnFrame;
        if (GodotObject.IsInstanceValid(component))
        {
            component.TreeExiting -= Dispose;
            if (component.IsConnected("action_finished", completed)) component.Disconnect("action_finished", completed);
        }
        foreach (var request in pending)
            request.Value.TrySetResult(new Completion(request.Key, false, "Viewer component lifetime ended", null, null, null));
        pending.Clear();
    }
}

/// <summary>Original MuJoCo panels and interaction; no Godot Extras dependency.</summary>
public sealed class ViewerHandle : RuntimeUiHandle
{
    private ViewerHandle(Node node) : base(node) { }
    public static Access<ViewerHandle> Bind(Node node) =>
        IsComponent(node, "res://addons/godot_mujoco/viewer/runtime_viewer.gd")
        ? Access<ViewerHandle>.Ok(new ViewerHandle(node))
        : Access<ViewerHandle>.Fail("Bind an explicit live MjRuntimeViewer on the main thread");
    public Request SetControl(int id, double value) => Execute("control", new GDictionary{{"id",id},{"value",value}});
    public Request SetJoint(int id, double value) => Execute("joint", new GDictionary{{"id",id},{"value",value}});
    public Request SetEquality(int id, bool active) => Execute("equality", new GDictionary{{"id",id},{"value",active}});
    public Request ResetInitial() => Execute("reset_initial");
    public Operation ShowNativePanels(bool left, bool right) => View("show_native_panels", left, right);
    public Operation ShowInfo(bool enabled) => View("show_info", enabled);
}

/// <summary>Independent F11 tools and performance display, directly bound to a World or Host.</summary>
public sealed class ExtrasHandle : RuntimeUiHandle
{
    private ExtrasHandle(Node node) : base(node) { }
    public static Access<ExtrasHandle> Bind(Node node) =>
        IsComponent(node, "res://addons/godot_mujoco/viewer/godot_extras.gd")
        ? Access<ExtrasHandle>.Ok(new ExtrasHandle(node))
        : Access<ExtrasHandle>.Fail("Bind an explicit live MjGodotExtras on the main thread");
    public Request CaptureSnapshot() => Execute("capture_snapshot");
    public Request RestoreSnapshot() => Execute("restore_snapshot");
    public Operation ShowPerformance(bool enabled) => View("show_performance", enabled);
    public Operation ShowExtras(bool visible) => View("show_extras", visible);
}
