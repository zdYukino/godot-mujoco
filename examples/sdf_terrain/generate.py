#!/usr/bin/env python3
"""Original deterministic, metre/Y-up, watertight terrain; Python stdlib only."""
import argparse, collections, hashlib, json, math, random
from pathlib import Path
SEED=20261026
def cross2(a,b,c): return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def triangulate(poly):
    ids=list(range(len(poly)))
    if sum(poly[i][0]*poly[(i+1)%len(poly)][1]-poly[(i+1)%len(poly)][0]*poly[i][1] for i in ids)<0: ids.reverse()
    triangles=[]
    while len(ids)>3:
        for k,b in enumerate(ids):
            a,c=ids[k-1],ids[(k+1)%len(ids)]
            if cross2(poly[a],poly[b],poly[c])<=1e-12: continue
            def inside(p): return min(cross2(poly[a],poly[b],p),cross2(poly[b],poly[c],p),cross2(poly[c],poly[a],p))>=-1e-12
            if any(inside(poly[d]) for d in ids if d not in (a,b,c)): continue
            triangles.append((a,b,c)); ids.pop(k); break
        else: raise ValueError("Non-simple/degenerate profile")
    triangles.append(tuple(ids))
    return triangles
def validate(vertices,faces):
    edges=collections.defaultdict(list); volume=0.
    for f in faces:
        a,b,c=[vertices[i] for i in f]
        ab=[b[k]-a[k] for k in range(3)]; ac=[c[k]-a[k] for k in range(3)]
        normal=[ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0]]
        if sum(x*x for x in normal)<1e-16: raise ValueError("Degenerate triangle")
        volume+=(a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6
        for u,v in zip(f,(*f[1:],f[0])): edges[min(u,v),max(u,v)].append(1 if u<v else -1)
    if any(len(v)!=2 or sum(v)!=0 for v in edges.values()): raise ValueError("Not a closed oriented 2-manifold")
    if volume<0: faces=[(a,c,b) for a,b,c in faces]; volume=-volume
    if volume<=1e-8 or len(faces)>2000: raise ValueError("Terrain volume/budget invalid")
    return faces,volume
def stairs():
    poly=[(-1.5,0.)]
    for k in range(6):
        x=-1.5+(k+1)*.5; y=k*.18
        poly.append((x,y))
        if k<5: poly.append((x,(k+1)*.18))
    poly += [(1.5,-.25),(-1.5,-.25)]
    verts=[(x,y,z) for z in (-1.,1.) for x,y in poly]
    n=len(poly); faces=[]
    for a,b,c in triangulate(poly): faces += [(a,c,b),(a+n,b+n,c+n)]
    area=sum(poly[i][0]*poly[(i+1)%n][1]-poly[(i+1)%n][0]*poly[i][1] for i in range(n))
    order=list(range(n)) if area>0 else list(reversed(range(n)))
    for a,b in zip(order,order[1:]+order[:1]): faces += [(a,b,b+n),(a,b+n,a+n)]
    return verts,faces
def grid(height,n=12,bottom=-.6):
    coords=[-1+2*i/n for i in range(n+1)]; m=(n+1)**2
    verts=[(x,height(x,z),z) for z in coords for x in coords]+[(x,bottom,z) for z in coords for x in coords]
    faces=[]
    for j in range(n):
        for i in range(n):
            a=j*(n+1)+i;b=a+1;c=a+n+1;d=c+1
            faces += [(a,c,b),(b,c,d),(a+m,b+m,c+m),(b+m,d+m,c+m)]
    boundary=list(range(n+1))+[j*(n+1)+n for j in range(1,n+1)]+[n*(n+1)+i for i in range(n-1,-1,-1)]+[j*(n+1) for j in range(n-1,0,-1)]
    for a,b in zip(boundary,boundary[1:]+boundary[:1]): faces += [(a,b,b+m),(a,b+m,a+m)]
    return verts,faces
def depression(x,z):
    r=max(abs(x),abs(z))
    return -.35 if r<=.45 else .30 if r>=.8 else -.35+.65*(r-.45)/.35
def generate(out):
    out.mkdir(parents=True,exist_ok=True); rng=random.Random(SEED)
    noise={(i,j):rng.uniform(-.10,.10) for j in range(13) for i in range(13)}
    def rough(x,z): return .16+noise[round((x+1)*6),round((z+1)*6)]+.04*math.sin(4*x)*math.cos(3*z)
    chunks=[("stairs",stairs(),-3.),("depression",grid(depression),0.),("rough",grid(rough),3.)]
    obj=["# Original deterministic closed terrain; metres; Y_UP; seed="+str(SEED)]
    manifest={"seed":SEED,"units":"m","axes":"Y_UP","grid_cells":12,"octree_maxdepth":6,"stairs":{"steps":6,"depth_m":.5,"rise_m":.18},"depression":{"floor_y_m":-.35,"rim_y_m":.30,"floor_halfwidth_m":.45},"chunks":[]}
    base=1
    for name,(verts,faces),offset in chunks:
        faces,volume=validate(verts,faces)
        obj.append("o "+name)
        obj += ["v %.12f %.12f %.12f"%(x+offset,y,z) for x,y,z in verts]
        obj += ["f "+" ".join(str(base+i) for i in f) for f in faces]
        manifest["chunks"].append({"name":name,"offset_x_m":offset,"vertices":len(verts),"triangles":len(faces),"volume_m3":volume})
        base+=len(verts)
    payload=("\n".join(obj)+"\n").encode(); (out/"terrain.obj").write_bytes(payload)
    manifest["obj_sha256"]=hashlib.sha256(payload).hexdigest()
    (out/"parameters.json").write_text(json.dumps(manifest,indent=2)+"\n")
    print(json.dumps(manifest))
if __name__=="__main__":
    ap=argparse.ArgumentParser();ap.add_argument("--out",type=Path,default=Path(__file__).parent/"assets")
    generate(ap.parse_args().out)
