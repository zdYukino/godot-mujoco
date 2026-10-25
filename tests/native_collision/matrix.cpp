#include <mujoco/mujoco.h>
#include <cstdio>
int main(){
 if(mj_version()!=3016000)return 2;
 const char* names[]={"plane","hfield","sphere","capsule","ellipsoid","cylinder","box","mesh","sdf"};
 bool ok=true;
 for(int a=0;a<9;++a)for(int b=a;b<9;++b){
  bool present=mjCOLLISIONFUNC[a][b]!=nullptr;
  bool absent=(a==0&&b==0)||(a==0&&b==1)||(a==1&&b==1);
  std::printf("%s,%s,%s\n",names[a],names[b],present?"dispatcher_present_not_general_validation":"unsupported");
  if(present==absent)ok=false;
 }
 mjOption o;mj_defaultOption(&o);
 std::printf("defaults nativeccd=%d multiccd=%d solver=%d cone=%d\n",!(o.disableflags&mjDSBL_NATIVECCD),!(o.disableflags&mjDSBL_MULTICCD),o.solver,o.cone);
 return ok?0:1;
}
