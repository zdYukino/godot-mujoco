#pragma once
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/string.hpp>
#include <mujoco/mujoco.h>
namespace godot {
inline mjSpec *gmj_import_g1(const String &path, String &error_message){
 String absolute=path;
 if(!FileAccess::file_exists(absolute)){error_message="URDF file does not exist";return nullptr;}
 char error[2048]={};mjSpec *spec=mj_parseXML(absolute.utf8().get_data(),nullptr,error,sizeof(error));
 if(!spec){error_message=String::utf8(error);return nullptr;}
 // G1's URDF repeats meshes/ in meshdir and filenames. Resolve copies of
 // the spec's paths to absolute files; never rewrite the upstream URDF/assets.
 spec->strippath=false;mjs_setString(spec->compiler.meshdir,"");
 for(auto*e=mjs_firstElement(spec,mjOBJ_MESH);e;e=mjs_nextElement(spec,e)){
  auto*m=mjs_asMesh(e);String name=String::utf8(mjs_getString(m->file)).get_file();
  String resolved=absolute.get_base_dir().path_join("meshes").path_join(name);mjs_setString(m->file,resolved.utf8().get_data());
 }
 mjModel *source=mj_compile(spec,nullptr);
 if(!source){error_message=String::utf8(mjs_getError(spec));mj_deleteSpec(spec);return nullptr;}
 bool compatible=source->njnt==29&&source->nq==29&&source->nv==29&&source->nu==0&&source->nmesh==34;
 mj_deleteModel(source);
 if(!compatible){error_message="Expected fixed-base G1 URDF: 29 hinge joints, 34 meshes, no source actuators";mj_deleteSpec(spec);return nullptr;}
 // Explicit synthetic bounded position drives, not a Unitree controller.
 // Compensation holds the fixed-base robot against gravity; world gravity
 // and robot/obstacle contacts remain enabled. Self-contact is excluded by mask.
 for(auto*e=mjs_firstElement(spec,mjOBJ_BODY);e;e=mjs_nextElement(spec,e))mjs_asBody(e)->gravcomp=1;
 for(auto*e=mjs_firstElement(spec,mjOBJ_GEOM);e;e=mjs_nextElement(spec,e)){auto*g=mjs_asGeom(e);if(g->contype||g->conaffinity){g->contype=2;g->conaffinity=1;}}
 for(auto*e=mjs_firstElement(spec,mjOBJ_JOINT);e;e=mjs_nextElement(spec,e)){
  auto*j=mjs_asJoint(e);if(j->type!=mjJNT_HINGE){error_message="G1 joints must be hinges";mj_deleteSpec(spec);return nullptr;}
  const char *name=mjs_getString(mjs_getName(e));auto*a=mjs_addActuator(spec,nullptr);
  mjs_setName(a->element,(std::string(name)+"_position").c_str());mjs_setString(a->target,name);
  a->trntype=mjTRN_JOINT;a->gear[0]=1;a->gaintype=mjGAIN_FIXED;a->gainprm[0]=100;
  a->biastype=mjBIAS_AFFINE;a->biasprm[1]=-100;a->biasprm[2]=-10;
  a->ctrllimited=mjLIMITED_TRUE;a->ctrlrange[0]=j->range[0];a->ctrlrange[1]=j->range[1];
  a->forcelimited=mjLIMITED_TRUE;a->forcerange[0]=j->actfrcrange[0];a->forcerange[1]=j->actfrcrange[1];
 }
 spec->option.integrator=mjINT_IMPLICITFAST;
 spec->option.gravity[2]=-9.8;
 return spec;
}
}
