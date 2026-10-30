using Godot;
using GDictionary = Godot.Collections.Dictionary;

namespace GodotMuJoCo;

/// <summary>Shared runtime viewer. Rebind after its world is replaced.</summary>
public sealed class ViewerHandle : RuntimeHandle
{
    private readonly ulong worldId;
    protected override string PendingProperty => "command_request";
    protected override bool SameLifetime => Node.Get("runtime_world").AsGodotObject() is Node world &&
        GodotObject.IsInstanceValid(world) && world.GetInstanceId() == worldId;
    private ViewerHandle(Node node, Node world) : base(node, "viewer_command_finished") => worldId=world.GetInstanceId();
    public static Access<ViewerHandle> Bind(Node world)
    {
        if (!IsScript(world,"runtime_world.gd") || world.Get("runtime_viewer").AsGodotObject() is not Node viewer ||
            !GodotObject.IsInstanceValid(viewer)) return Access<ViewerHandle>.Fail("Expected a world with an active RuntimeViewer");
        return Access<ViewerHandle>.Ok(new ViewerHandle(viewer,world));
    }
    /// <summary>Revisioned, value-only frame plus capabilities in catalog; no mjModel/mjData pointers.</summary>
    public Access<GDictionary> Read() => IsAlive
        ? Access<GDictionary>.Ok(Node.Get("frame").AsGodotDictionary().Duplicate())
        : Access<GDictionary>.Fail(Unavailable);
    public Request Execute(GDictionary command) => Queue("request_action",command);
    public Request Cancel() => Execute(new GDictionary{{"action","cancel"}});
    public Request SetControl(int id,double value) => Execute(new GDictionary{{"action","control"},{"id",id},{"value",value}});
    public Request SetJoint(int id,double value) => Execute(new GDictionary{{"action","joint"},{"id",id},{"value",value}});
    public Request SetEquality(int id,bool active) => Execute(new GDictionary{{"action","equality"},{"id",id},{"value",active}});
    public Request CaptureSnapshot() => Execute(new GDictionary{{"action","capture_snapshot"}});
    public Request RestoreSnapshot() => Execute(new GDictionary{{"action","restore_snapshot"}});
    public Request ResetInitial() => Execute(new GDictionary{{"action","reset_initial"}});
    /// <summary>Show only the Godot extras window (F11).</summary>
    public void ShowControls(bool visible) { if(IsAlive)Node.Call("set_controls_visible",visible); }
    /// <summary>Godot FPS/system-performance overlay, independent of MuJoCo Info.</summary>
    public void SetOverlay(bool enabled) { if(IsAlive)Node.Call("set_overlay",enabled); }
    public void ShowNativePanels(bool left, bool right) { if(IsAlive)Node.Call("set_native_panels",left,right); }
    public void SetInfo(bool enabled) { if(IsAlive)Node.Call("set_info",enabled); }
}
