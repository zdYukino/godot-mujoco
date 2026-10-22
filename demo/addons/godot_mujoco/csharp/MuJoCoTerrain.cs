using Godot;
using System;
using System.Collections.Generic;
using GDictionary = Godot.Collections.Dictionary;

namespace GodotMuJoCo;

/// <summary>Immutable copied static grid design. One metre spacing, local X/Z row order.</summary>
public sealed class TerrainDesign
{
    private readonly float[] heights;
    public int Width { get; }
    public int Depth { get; }
    public IReadOnlyList<float> Heights { get; }
    public Transform3D Pose { get; }
    public uint Layer { get; }
    public uint Mask { get; }
    private TerrainDesign(int width, int depth, float[] values, Transform3D pose, uint layer, uint mask)
    {
        Width=width; Depth=depth; heights=values; Heights=Array.AsReadOnly(values);
        Pose=pose; Layer=layer; Mask=mask;
    }
    public static Access<TerrainDesign> Create(int width, int depth, IReadOnlyList<float> values,
        Transform3D? pose=null, uint layer=1, uint mask=1)
    {
        if(width<2 || depth<2 || width>256 || depth>256 || values==null || values.Count!=width*depth)
            return Access<TerrainDesign>.Fail("Expected 2..256 dimensions and exactly width*depth samples");
        var copy=new float[values.Count];
        for(int i=0;i<copy.Length;i++) {
            if(!float.IsFinite(values[i]) || Math.Abs(values[i])>10000)
                return Access<TerrainDesign>.Fail("Heights must be finite and within +/-10000 metres");
            copy[i]=values[i];
        }
        var transform=pose ?? Transform3D.Identity;
        var b=transform.Basis;
        if(!transform.IsFinite() || Math.Abs(b.X.LengthSquared()-1)>1e-5 ||
            Math.Abs(b.Y.LengthSquared()-1)>1e-5 || Math.Abs(b.Z.LengthSquared()-1)>1e-5 ||
            Math.Abs(b.X.Dot(b.Y))>1e-5 || Math.Abs(b.Y.Dot(b.Z))>1e-5 ||
            Math.Abs(b.X.Dot(b.Z))>1e-5 || b.Determinant()<=0)
            return Access<TerrainDesign>.Fail("Expected a finite rigid pose, without scale/shear");
        return Access<TerrainDesign>.Ok(new TerrainDesign(width,depth,copy,transform,layer,mask));
    }
    internal GDictionary Snapshot() => new() {
        ["width"]=Width,["depth"]=Depth,["heights"]=(float[])heights.Clone(),
        ["pose"]=Pose,["layer"]=(long)Layer,["mask"]=(long)Mask
    };
    internal static TerrainDesign FromSnapshot(GDictionary data) => new(
        data["width"].AsInt32(),data["depth"].AsInt32(),data["heights"].AsFloat32Array(),
        data["pose"].AsTransform3D(),data["layer"].AsUInt32(),data["mask"].AsUInt32());
}

public sealed record TerrainState(string Identity, long Generation, long Revision, bool Active,
    long PendingRequest, string Error, TerrainDesign? CommittedDesign);

/// <summary>One node/terrain generation. Successful removal invalidates this handle; rebind to add again.</summary>
public sealed class TerrainHandle : RuntimeHandle
{
    private const string ScriptPath="res://addons/godot_mujoco/model/static_heightfield.gd";
    private readonly string identity;
    private readonly long generation;
    protected override string PendingProperty => "pending_request";
    protected override bool SameLifetime => Node.Get("live_id").AsString()==identity &&
        Node.Get("generation").AsInt64()==generation;
    /// <summary>Only set by Create. Accepted means queued; await Finished for native success.</summary>
    public Request? InitialRequest { get; private set; }
    private TerrainHandle(Node node) : base(node,"edit_finished")
    { identity=node.Get("live_id").AsString();generation=node.Get("generation").AsInt64(); }
    public static Access<TerrainHandle> Bind(Node node)
    {
        if(!IsScript(node,"static_heightfield.gd") || node.Get("live_id").AsString().Length==0)
            return Access<TerrainHandle>.Fail("Expected a live MjStaticHeightField (or inherited script)");
        return Access<TerrainHandle>.Ok(new TerrainHandle(node));
    }
    public static Access<TerrainHandle> Create(Node3D parent, string name, TerrainDesign design)
    {
        if(OS.GetThreadCallerId()!=OS.GetMainThreadId())
            return Access<TerrainHandle>.Fail("Create terrain on the Godot main thread");
        if(!GodotObject.IsInstanceValid(parent) || parent.IsQueuedForDeletion() || !parent.IsInsideTree() ||
            !parent.GetWorld3D().HasMeta("mj_runtime_owner"))
            return Access<TerrainHandle>.Fail("Expected a live parent in a configured MuJoCo world");
        if(design==null || string.IsNullOrWhiteSpace(name) || name=="." || name==".." ||
            name.IndexOfAny(new[]{'/','\\',':','@','\"','%'})>=0 || parent.HasNode(new NodePath(name)))
            return Access<TerrainHandle>.Fail("Choose a valid design and unused node name");
        var node=(Node3D)GD.Load<GDScript>(ScriptPath).New().AsGodotObject();
        node.Name=name;node.Set("auto_apply",false);parent.AddChild(node);
        node.Owner=parent.Owner ?? parent;
        var handle=new TerrainHandle(node);
        handle.InitialRequest=handle.Update(design,0);
        if(!handle.InitialRequest.Accepted) {
            string error=handle.InitialRequest.Error;handle.Dispose();node.QueueFree();
            return Access<TerrainHandle>.Fail(error);
        }
        node.Set("auto_apply",true);
        return Access<TerrainHandle>.Ok(handle);
    }
    public Access<TerrainState> Read()
    {
        if(!IsAlive) return Access<TerrainState>.Fail(Unavailable);
        // Poll completion before taking a snapshot, so revision/design cannot straddle a commit.
        var data=Node.Call("state").AsGodotDictionary();
        if(!IsAlive) return Access<TerrainState>.Fail(Unavailable);
        var committed=data["committed"].AsGodotDictionary();
        return Access<TerrainState>.Ok(new TerrainState(identity,generation,data["revision"].AsInt64(),
            data["active"].AsBool(),data["pending"].AsInt64(),data["error"].AsString(),
            committed.Count==0 ? null : TerrainDesign.FromSnapshot(committed)));
    }
    public Request Update(TerrainDesign design,long expectedRevision)
    {
        if(design==null || expectedRevision<0) return Request.Rejected("A valid design and explicit revision are required");
        return Queue("request_snapshot",design.Snapshot(),expectedRevision);
    }
    public Request Remove() => Queue("request_remove");
}
