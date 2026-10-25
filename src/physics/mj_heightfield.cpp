#include "mj_physics_server.h"
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <cmath>
namespace godot {
namespace {
String validate(const Dictionary &v){
 if(v.get("width",Variant()).get_type()!=Variant::INT||v.get("depth",Variant()).get_type()!=Variant::INT||v.get("heights",Variant()).get_type()!=Variant::PACKED_FLOAT32_ARRAY||v.get("pose",Variant()).get_type()!=Variant::TRANSFORM3D)return "Expected width, depth, PackedFloat32Array heights and rigid pose";
 int64_t w=v["width"],d=v["depth"];PackedFloat32Array h=v["heights"];
 if(w<2||d<2||w>256||d>256||h.size()!=w*d)return "Grid dimensions must be 2..256 with exactly width*depth samples";
 for(int i=0;i<h.size();++i)if(!std::isfinite(h[i])||std::abs(h[i])>10000)return "Heights must be finite and within +/-10000 metres; holes are unsupported";
 for(const char *key:{"layer","mask"})if(v.get(key,1).get_type()!=Variant::INT||int64_t(v.get(key,1))<0||uint64_t(int64_t(v.get(key,1)))>0xffffffffu)return "Collision layer/mask must be unsigned 32-bit integers";
 Variant friction=v.get("friction",1.0);
 if((friction.get_type()!=Variant::FLOAT&&friction.get_type()!=Variant::INT)||!std::isfinite(double(friction))||std::abs(double(friction))>1)return "Heightfield friction must be finite within -1..1 (negative means rough)";
 Variant bounce=v.get("bounce",0.0);
 if((bounce.get_type()!=Variant::FLOAT&&bounce.get_type()!=Variant::INT)||double(bounce)!=0)return "Heightfield nonzero bounce is unsupported";
 Transform3D t=v["pose"];
 if(!t.is_finite()||!t.basis.is_orthogonal()||!t.basis.get_scale().is_equal_approx(Vector3(1,1,1))||t.basis.determinant()<0)return "Heightfield pose must be rigid (no scale/shear)";
 return {};
}
}
int64_t MjPhysicsServer3D::scene_request_heightfield(const RID&s,const RID&b,const Dictionary&v,uint64_t owner,int64_t revision){
 std::lock_guard<std::mutex> lock(edits_mutex);
 if(heightfield_edits.size()>=64||heightfield_results.size()>=256)return 0;
 for(auto &e:heightfield_edits)if(e.owner==owner)return 0;
 int64_t id=next_edit_request++;heightfield_edits.push_back({id,revision,s,b,v.duplicate(true),owner});return id;
}
Dictionary MjPhysicsServer3D::scene_heightfield_result(int64_t id){std::lock_guard<std::mutex> lock(edits_mutex);auto it=heightfield_results.find(id);if(it==heightfield_results.end())return {};Dictionary v=it->second;heightfield_results.erase(it);return v;}
void MjPhysicsServer3D::scene_cancel_heightfield(int64_t id){std::lock_guard<std::mutex> lock(edits_mutex);for(auto it=heightfield_edits.begin();it!=heightfield_edits.end();++it)if(it->request==id){heightfield_edits.erase(it);break;}
 // A completed add can outlive its node's polling callback. Free its owned body
 // when the observer exits, including results not yet consumed.
 auto it=heightfield_results.find(id);if(it!=heightfield_results.end()){RID b=it->second.get("body",RID());if(bool(it->second.get("success",false))&&b.is_valid())_free_rid(b);heightfield_results.erase(it);}}
void MjPhysicsServer3D::process_heightfields(){
 std::deque<HeightfieldEdit> pending;{std::lock_guard<std::mutex> lock(edits_mutex);pending.swap(heightfield_edits);}
 for(auto &e:pending){Dictionary result;result["request"]=e.request;result["body"]=e.body;
 auto apply=[&]()->String{
 auto*s=space(e.space);if(!s||!s->authored_options)return "Configured runtime world was removed";
 if(!ObjectDB::get_instance(ObjectID(e.owner)))return "Heightfield owner was removed";
 auto*b=body(e.body);if(e.body.is_valid()&&(!b||!b->heightfield||b->space!=e.space||b->object_id!=e.owner))return "Stale or foreign heightfield body";
 int64_t rev=b?heightfield_revisions[e.body.get_id()]:0;result["revision"]=rev;
 if(e.revision!=rev)return "Stale heightfield revision";
 bool remove=e.design.is_empty();if(remove&&!b)return "No heightfield to remove";
 if(!remove){String error=validate(e.design);if(!error.is_empty())return error;
 if(b){Dictionary old=shape(b->shapes[0].shape)->data;if(old["width"]!=e.design["width"]||old["depth"]!=e.design["depth"])return "Resolution is fixed; remove before adding a different grid";}}
 if(!rebuild(*s))return s->last_error;
 bool was_paused=s->paused;s->paused=true;
 RID id=e.body;bool added=!b;Dictionary old;Transform3D old_pose;uint32_t old_layer=1,old_mask=1;double old_friction=b?double(_body_get_param(id,BODY_PARAM_FRICTION)):1.0;
 if(added){id=_body_create();b=body(id);b->heightfield=true;b->mode=BODY_MODE_STATIC;b->object_id=e.owner;b->space=e.space;b->shapes.push_back({make_shape(SHAPE_HEIGHTMAP,e.design),Transform3D(),false});}
 else{old=shape(b->shapes[0].shape)->data;old_pose=b->transform;old_layer=b->layer;old_mask=b->mask;}
 if(remove)b->space=RID();else{shape(b->shapes[0].shape)->data=e.design;b->transform=e.design["pose"];b->layer=e.design.get("layer",1);b->mask=e.design.get("mask",1);b->params[BODY_PARAM_FRICTION]=e.design.get("friction",1.0);}
 s->dirty=true;bool ok=rebuild(*s);String error=s->last_error;
 if(!ok){if(added)_free_rid(id);else{b->space=e.space;b->transform=old_pose;b->layer=old_layer;b->mask=old_mask;b->params[BODY_PARAM_FRICTION]=old_friction;shape(b->shapes[0].shape)->data=old;}s->dirty=false;}
 else if(remove){_free_rid(id);result["body"]=RID();result["revision"]=rev+1;}
 else{heightfield_revisions[id.get_id()]=rev+1;result["body"]=id;result["revision"]=rev+1;}
 s->paused=was_paused;
 return ok?String():error;
 };String error=apply();result["success"]=error.is_empty();result["error"]=error;
 std::lock_guard<std::mutex> lock(edits_mutex);heightfield_results[e.request]=result;
 }
}
}
