#pragma once
#include <mujoco/mujoco.h>
#include <algorithm>
// Shared transactional migration for native spaces and isolated editor previews.
inline void gmj_transfer_state(const mjModel *old_model, const mjData *old_data,
                               const mjModel *model, mjData *data) {
 if (!old_model || !old_data) return;
  data->time=old_data->time;
  for(int j=0;j<model->njnt;++j){const char *name=mj_id2name(model,mjOBJ_JOINT,j);if(!name)continue;
   int old=mj_name2id(old_model,mjOBJ_JOINT,name);if(old<0||model->jnt_type[j]!=old_model->jnt_type[old])continue;
   int nq=model->jnt_type[j]==mjJNT_FREE?7:(model->jnt_type[j]==mjJNT_BALL?4:1);
   int nv=model->jnt_type[j]==mjJNT_FREE?6:(model->jnt_type[j]==mjJNT_BALL?3:1);
   std::copy_n(old_data->qpos+old_model->jnt_qposadr[old],nq,data->qpos+model->jnt_qposadr[j]);
   std::copy_n(old_data->qvel+old_model->jnt_dofadr[old],nv,data->qvel+model->jnt_dofadr[j]);
   std::copy_n(old_data->qacc_warmstart+old_model->jnt_dofadr[old],nv,data->qacc_warmstart+model->jnt_dofadr[j]);
  }
  for(int a=0;a<model->nu;++a){const char *name=mj_id2name(model,mjOBJ_ACTUATOR,a);if(!name)continue;int old=mj_name2id(old_model,mjOBJ_ACTUATOR,name);if(old>=0)data->ctrl[a]=old_data->ctrl[old];}
  for(int a=0;a<model->nu;++a){
   const char*n=mj_id2name(model,mjOBJ_ACTUATOR,a);if(!n)continue;
   int old=mj_name2id(old_model,mjOBJ_ACTUATOR,n);
   if(old<0||model->actuator_dyntype[a]!=old_model->actuator_dyntype[old]||model->actuator_actnum[a]!=old_model->actuator_actnum[old])continue;
   if(model->actuator_actnum[a])std::copy_n(old_data->act+old_model->actuator_actadr[old],model->actuator_actnum[a],data->act+model->actuator_actadr[a]);
  }
  for(int b=1;b<model->nbody;++b){int dst=model->body_mocapid[b];const char*n=mj_id2name(model,mjOBJ_BODY,b);if(dst<0||!n)continue;int old=mj_name2id(old_model,mjOBJ_BODY,n);if(old<0)continue;int src=old_model->body_mocapid[old];if(src<0)continue;std::copy_n(old_data->mocap_pos+3*src,3,data->mocap_pos+3*dst);std::copy_n(old_data->mocap_quat+4*src,4,data->mocap_quat+4*dst);}
}
