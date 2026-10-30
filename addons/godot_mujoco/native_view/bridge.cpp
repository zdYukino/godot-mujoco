// Experimental runtime-only Linux/GLX display transport; no independent physics stepping.
// All GL/MuJoCo objects live on Godot's render thread. Shared-texture reuse has
// fences in BOTH directions; an import stays alive until the main thread has
// replaced all canvas references and acknowledged the newer generation.
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>
#include <GL/glx.h>
#include <GL/glxext.h>
#include <X11/Xlib.h>
#include <mujoco/mujoco.h>
#include "../../../src/physics/mj_native_view_budget.h"
#include "../../../src/physics/mj_dictionary_compat.h"
#include <atomic>
#include <memory>
#include <malloc.h>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/json.hpp>
#include <cstdlib>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <deque>
#include <fstream>
#include <mutex>
#include <string>
#include <vector>

using namespace godot;
static std::atomic<void*> display_owner{nullptr};
// Linker wrappers observe bridge-origin step calls. They do not claim to
// intercept other DSOs' internal calls.
static std::atomic<int64_t> bridge_step_calls{0};
extern "C" void __real_mj_step(const mjModel*,mjData*);
extern "C" void __real_mj_step1(const mjModel*,mjData*);
extern "C" void __real_mj_step2(const mjModel*,mjData*);
extern "C" void __wrap_mj_step(const mjModel*m,mjData*d){++bridge_step_calls;__real_mj_step(m,d);}
extern "C" void __wrap_mj_step1(const mjModel*m,mjData*d){++bridge_step_calls;__real_mj_step1(m,d);}
extern "C" void __wrap_mj_step2(const mjModel*m,mjData*d){++bridge_step_calls;__real_mj_step2(m,d);}

using Clock = std::chrono::steady_clock;
static double elapsed(Clock::time_point a, Clock::time_point b) {
  return std::chrono::duration<double, std::milli>(b-a).count();
}

class MjSharedNativeViewBridge : public Node {
  GDCLASS(MjSharedNativeViewBridge, Node)
  struct Slot { GLuint texture=0, fbo=0, depth=0; RID rid; int width=0, height=0, generation=0; };
  struct Request {int width=0,height=0,action=-1;double dx=0,dy=0;bool running=false,reload=false;String path;double phase=0;int ui_serial=0;bool previous_visible=false;};
  Request queued;
  Dictionary queued_shared, render_shared;
  std::mutex mutex;
  Dictionary published;
  bool pending=false, closed=false, terminal_failure=false;
  int acknowledged=0, generation=0, frame=0, allocations=0, releases=0, model_generation=0;
  int max_live=0, gl_errors=0, shared_checks=0;
  GLuint queries[8]{};
  GLuint timestamps[8][3]{};
  bool query_pending[8]{};
  double gpu_ms=-1;
  double render_gpu_ms=-1, blit_gpu_ms=-1;
  RID viewport;
  bool direct_fbo=false;
  String capture_path;
  int capture_width=0,capture_height=0;
  Dictionary capture_result;
  GLXDrawable presentation_window=0;
  int presentation_swaps=0,presentation_errors=0;
  int presentation_native_frame=0,presentation_ui_serial=0;
  int64_t presentation_completed_usec=0;
  double presentation_cpu_ms=0;
  Display *presentation_display=nullptr;
  GLXContext presentation_context=nullptr;
  Dictionary presentation_binding;
  struct PresentRequest {int serial=0,width=0,height=0;};
  std::deque<PresentRequest> presentation_queue;
  bool audit_present=false,drain_present=false,release_none=false,present_before_produce=false;
  int core_release_behavior=-1,producer_release_behavior=-1;
  int presentation_readbacks=0,presentation_bad_markers=0;
  int presentation_ui_mismatch=0,presentation_native_mismatch=0;
  double presentation_drain_ms=0;
  Array presentation_trace;
  int gpu_samples=0;
  PackedStringArray reference_names;std::vector<int> reference_ids;
  bool reference_view=false; mjvGLCamera reference_camera{};
  bool fixture_camera=false;
  bool scene_ready=false;
  double camera_transfer_error=-1;
  mjvGLCamera base_camera{};
  std::array<double,3> camera_center{};
  std::vector<int> visible;
  Display *display=nullptr;
  GLXContext compat=nullptr;
  GLXPbuffer pbuffer=0;
  mjModel *model=nullptr;
  mjData *data=nullptr;
  int64_t resident_bytes=0,serialized_bytes=0;
  int model_allocations=0,model_releases=0,data_allocations=0,data_releases=0;
  const bool state_audit=std::getenv("GMJ_DIAGNOSTIC_STATE")!=nullptr;
  int64_t restore_checks=0,forward_checks=0,restore_mismatches=0,forward_mismatches=0;
  std::array<int64_t,16> input_changes{},forward_changes{};
  std::vector<mjtNum> state_readback,previous_state;
  double state_max_error=0;
  void compare_state(const PackedFloat64Array &expected,bool after_forward){
    state_readback.resize(expected.size());mj_getState(model,data,state_readback.data(),mjSTATE_INTEGRATION);
    int offset=0;bool bad=false;
    for(int bit=0;bit<16;++bit){if(!(mjSTATE_INTEGRATION&(1<<bit)))continue;const int count=mj_stateSize(model,1<<bit);
      for(int j=0;j<count;++j){const int i=offset+j;if(state_readback[i]!=expected[i]){bad=true;state_max_error=std::max(state_max_error,std::abs(state_readback[i]-expected[i]));if(after_forward)++forward_changes[bit];}
        if(!after_forward&&previous_state.size()==size_t(expected.size())&&previous_state[i]!=expected[i])++input_changes[bit];}
      offset+=count;
    }
    if(after_forward){++forward_checks;if(bad)++forward_mismatches;}
    else {++restore_checks;if(bad)++restore_mismatches;previous_state.assign(expected.ptr(),expected.ptr()+expected.size());}
  }
  bool shared_buffer_identity=true;int64_t serialized_payloads=0;

  mjvScene scene{};
  mjrContext render{};
  mjvOption options{};
  mjvCamera camera{};
  Slot current;
  std::vector<Slot> retired;
  std::string model_path;
  std::string core_version, compat_version, vendor, renderer, error;
  int core_profile=0, compat_profile=0;

  struct Binding {Display *display=nullptr;GLXContext context=nullptr;GLXDrawable draw=0,read=0;};
  Binding home;
  std::vector<GLsync> live_syncs;
  String fault_point,fault_output;
  int fault_at=1,fault_seen=0,fault_injected=0;
  bool permanent_restore_failure=false;
  int context_failures=0,sync_failures=0,recovery_drains=0,restore_recoveries=0,namespace_violations=0;
  bool cleanup_complete=false;
  static Binding current_binding(){return {glXGetCurrentDisplay(),glXGetCurrentContext(),glXGetCurrentDrawable(),glXGetCurrentReadDrawable()};}
  static bool matches(const Binding &b){return b.display&&b.context&&b.draw&&b.read&&glXGetCurrentDisplay()==b.display&&glXGetCurrentContext()==b.context&&glXGetCurrentDrawable()==b.draw&&glXGetCurrentReadDrawable()==b.read;}
  Binding producer_binding() const{return {display,compat,pbuffer,pbuffer};}
  bool inject(const char *stage){
    if(fault_point!=stage)return false;
    if(++fault_seen!=fault_at)return false;
    ++fault_injected;std::fprintf(stderr,"PROBE_FAULT %s\n",stage);return true;
  }
  void status(Dictionary &d){
    d["bridge_step_calls"]=int64_t(bridge_step_calls.load());d["state_audit_enabled"]=state_audit;
    if(state_audit){d["restore_checks"]=restore_checks;d["forward_checks"]=forward_checks;d["restore_mismatches"]=restore_mismatches;d["forward_mismatches"]=forward_mismatches;d["state_max_error"]=state_max_error;
      Array changed,forward;for(int i=0;i<16;++i){changed.append(input_changes[i]);forward.append(forward_changes[i]);}d["input_component_changes"]=changed;d["forward_component_changes"]=forward;}
    d["model_allocations"]=model_allocations;d["model_releases"]=model_releases;d["data_allocations"]=data_allocations;d["data_releases"]=data_releases;
    d["resident_cpu_bytes"]=resident_bytes;d["serialized_bytes"]=serialized_bytes;d["serialized_payloads"]=serialized_payloads;
    d["shared_buffer_identity"]=shared_buffer_identity;d["vfs_staging_copies"]=0;

    d["context_failures"]=context_failures;d["sync_failures"]=sync_failures;d["recovery_drains"]=recovery_drains;d["restore_recoveries"]=restore_recoveries;d["namespace_violations"]=namespace_violations;d["fault_injected"]=fault_injected;d["live_syncs"]=int(live_syncs.size());d["cleanup_complete"]=cleanup_complete;d["entry_core_restored"]=matches(home);
  }
  [[noreturn]] void fatal_context(const char *reason){
    Dictionary d;status(d);d["fatal"]=true;d["reason"]=reason;d["exit_code"]=86;d["live_textures"]=allocations-releases;d["no_return_to_godot"]=true;
    if(!fault_output.is_empty()){std::ofstream f(fault_output.utf8().get_data());f<<JSON::stringify(d).utf8().get_data()<<"\n";}
    std::fprintf(stderr,"PROBE_FATAL_CONTEXT %s; refusing to return with an invalid context\n",reason);std::fflush(nullptr);std::_Exit(86);
  }
  bool checked_switch(const Binding &target,const char *stage){
    if(inject(stage)){++context_failures;return false;}
    if(!glXMakeContextCurrent(target.display,target.draw,target.read,target.context)||!matches(target)){++context_failures;return false;}
    return true;
  }
  bool drain(const Binding &target){
    if(!matches(target))return false;
    glFinish();++recovery_drains;
    return glGetError()==GL_NO_ERROR;
  }
  void restore_or_exit(const Binding &entry,bool producer_dirty){
    if(producer_dirty){
      if(!matches(producer_binding())&&!checked_switch(producer_binding(),"recovery-enter"))fatal_context("cannot reach producer to finish pending writes");
      if(!drain(producer_binding()))fatal_context("producer drain failed");
    }
    if(matches(entry))return;
    if(inject("restore-permanent"))permanent_restore_failure=true;
    if(permanent_restore_failure)fatal_context("injected permanent Core restoration failure");
    if(!checked_switch(entry,"recovery-restore")){
      // Separate fallback API is usable only when draw/read are the same window.
      if(entry.draw!=entry.read||!glXMakeCurrent(entry.display,entry.draw,entry.context)||!matches(entry))fatal_context("cannot restore entry Core context");
    }
    ++restore_recoveries;
  }
  struct ContextReturn {
    MjSharedNativeViewBridge *self;Binding entry;bool dirty=false;
    ~ContextReturn(){self->restore_or_exit(entry,dirty);}
  };
  void publish(Dictionary value){std::lock_guard<std::mutex> lock(mutex);published=value;pending=false;}
  void fail(const std::string &why){
    if(error.empty())error=why;
    {std::lock_guard<std::mutex> lock(mutex);terminal_failure=true;}
    Dictionary d=snapshot();d.erase("texture");d["error"]=String(error.c_str());status(d);publish(d);
  }
  GLsync fence(const char *stage){
    if(inject(stage)){++sync_failures;return nullptr;}
    GLsync result=glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0);
    GLenum issue=glGetError();
    if(!result||issue!=GL_NO_ERROR){if(result)glDeleteSync(result);++sync_failures;if(issue!=GL_NO_ERROR)++gl_errors;return nullptr;}
    live_syncs.push_back(result);glFlush();
    if(glGetError()!=GL_NO_ERROR){++sync_failures;++gl_errors;return nullptr;}
    return result;
  }
  bool wait(GLsync value,const char *stage){
    if(!value){++sync_failures;return false;}
    if(inject(stage)){++sync_failures;return false;}
    glWaitSync(value,0,GL_TIMEOUT_IGNORED);
    if(glGetError()!=GL_NO_ERROR){++sync_failures;++gl_errors;return false;}
    glDeleteSync(value);live_syncs.erase(std::remove(live_syncs.begin(),live_syncs.end(),value),live_syncs.end());return true;
  }
  void check_errors(){for(GLenum e=glGetError();e!=GL_NO_ERROR;e=glGetError())++gl_errors;}
  void adopt_camera(const mjvGLCamera &source) {
    for(int k=0;k<3;++k)camera.lookat[k]=camera_center[k];
    double norm=0;for(int k=0;k<3;++k)norm+=(source.pos[k]-camera_center[k])*(source.pos[k]-camera_center[k]);
    camera.distance=std::sqrt(norm);
    camera.azimuth=std::atan2(source.forward[1],source.forward[0])*180/3.141592653589793;
    camera.elevation=std::atan2(source.forward[2],std::hypot(source.forward[0],source.forward[1]))*180/3.141592653589793;
    camera.orthographic=source.orthographic;
  }

  static int release_behavior() {
    GLint major=0,minor=0,count=0;glGetIntegerv(GL_MAJOR_VERSION,&major);glGetIntegerv(GL_MINOR_VERSION,&minor);
    bool supported=major>4||(major==4&&minor>=5);
    if(!supported){glGetIntegerv(GL_NUM_EXTENSIONS,&count);for(int i=0;i<count;++i){const auto *ext=glGetStringi(GL_EXTENSIONS,i);if(ext&&std::strcmp(reinterpret_cast<const char*>(ext),"GL_KHR_context_flush_control")==0)supported=true;}}
    GLint value=-1;if(supported)glGetIntegerv(GL_CONTEXT_RELEASE_BEHAVIOR,&value);return value;
  }
  bool create_context() {
    display=glXGetCurrentDisplay(); GLXContext core=glXGetCurrentContext();
    home=current_binding();
    if(!display||!core){error="No current GLX context. Use X11 + gl_compatibility.";return false;}
    const auto *version=glGetString(GL_VERSION),*gl_vendor=glGetString(GL_VENDOR),*gl_renderer=glGetString(GL_RENDERER);
    if(!version||!gl_vendor||!gl_renderer){error="Core GL identity query failed";return false;}
    core_version=reinterpret_cast<const char*>(version);vendor=reinterpret_cast<const char*>(gl_vendor);renderer=reinterpret_cast<const char*>(gl_renderer);
    glGetIntegerv(GL_CONTEXT_PROFILE_MASK,&core_profile);
    core_release_behavior=release_behavior();
    int config_id=0;if(glXQueryContext(display,core,GLX_FBCONFIG_ID,&config_id)!=Success){error="Cannot query owning GLX FBConfig";return false;}
    int count=0; GLXFBConfig *configs=glXGetFBConfigs(display,DefaultScreen(display),&count);
    if(!configs||count<=0){error="No GLX FBConfigs available";return false;}
    GLXFBConfig config=nullptr;
    for(int i=0;i<count;++i){int id=0,types=0;glXGetFBConfigAttrib(display,configs[i],GLX_FBCONFIG_ID,&id);glXGetFBConfigAttrib(display,configs[i],GLX_DRAWABLE_TYPE,&types);if(id==config_id&&(types&GLX_PBUFFER_BIT)){config=configs[i];break;}}
    XFree(configs);
    if(!config){error="Godot FBConfig does not support a pbuffer";return false;}
    auto create=reinterpret_cast<PFNGLXCREATECONTEXTATTRIBSARBPROC>(glXGetProcAddressARB(reinterpret_cast<const GLubyte*>("glXCreateContextAttribsARB")));
    if(!create){error="GLX_ARB_create_context unavailable";return false;}
    std::vector<int> attrs={GLX_CONTEXT_MAJOR_VERSION_ARB,3,GLX_CONTEXT_MINOR_VERSION_ARB,3,GLX_CONTEXT_PROFILE_MASK_ARB,GLX_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB};
    if(release_none){
      const char *extensions=glXQueryExtensionsString(display,DefaultScreen(display));
      if(!extensions||!std::strstr(extensions,"GLX_ARB_context_flush_control")){error="GLX_ARB_context_flush_control unavailable";return false;}
      attrs.insert(attrs.end(),{GLX_CONTEXT_RELEASE_BEHAVIOR_ARB,GLX_CONTEXT_RELEASE_BEHAVIOR_NONE_ARB});
    }
    attrs.push_back(None);
    compat=inject("create-context")?nullptr:create(display,config,core,True,attrs.data());
    if(!compat){++context_failures;error="Cannot create compatibility context sharing Godot's core context";return false;}
    const int size[]={GLX_PBUFFER_WIDTH,1,GLX_PBUFFER_HEIGHT,1,None};
    pbuffer=inject("create-pbuffer")?0:glXCreatePbuffer(display,config,size);
    if(!pbuffer){++context_failures;error="Cannot create GLX pbuffer";return false;}
    return true;
  }
  void release_model() {
    if(model){mjr_freeContext(&render);mjv_freeScene(&scene);if(data){mj_deleteData(data);data=nullptr;++data_releases;}mj_deleteModel(model);model=nullptr;++model_releases;}
    resident_bytes=0;gmj_display::trace("display_released",0,model_generation);
  }
  bool load(const std::string &path) {
    PackedByteArray bytes=render_shared.get("model",PackedByteArray());
    if(bytes.is_empty()){error="Model revision changed without model bytes";return false;}
    Dictionary profile=render_shared.get("model_profile",Dictionary());
    const int64_t declared=profile.get("display_resident_estimate",int64_t(-1));
    if(bytes.size()>gmj_display::model_limit||declared<=0||declared>gmj_display::resident_limit){error="Display model admission budget rejected";return false;}
    const bool had_model=model!=nullptr;const mjvCamera previous_camera=camera;
    // No old/new CPU or mjr model overlap. The previous texture remains valid;
    // decode failure is terminal for this view and restores the Godot path.
    release_model();gmj_display::trace("decode_begin",bytes.size(),model_generation+1);
    if(inject("model-decode")){error="Injected display decode failure";return false;}
    std::unique_ptr<mjModel,decltype(&mj_deleteModel)> candidate_owner(mj_loadModelBuffer(bytes.ptr(),bytes.size()),&mj_deleteModel);
    mjModel *candidate=candidate_owner.get();
    if(!candidate){error="Cannot decode display model";return false;}++model_allocations;
    gmj_display::trace("decode_end",bytes.size(),model_generation+1);
    const int64_t data_buffer=profile.get("data_buffer_bytes",int64_t(-1));
    if(!gmj_display::decoded_admission(candidate,data_buffer,declared)){++model_releases;error="Display decoded model budget mismatch";return false;}
    std::unique_ptr<mjData,decltype(&mj_deleteData)> data_owner(inject("model-data")?nullptr:mj_makeData(candidate),&mj_deleteData);
    mjData *candidate_data=data_owner.get();
    if(!candidate_data){++model_releases;error="Cannot allocate display data";return false;}++data_allocations;
    if(!gmj_display::bounded(candidate_data->nbuffer,gmj_display::resident_limit)||int64_t(candidate_data->nbuffer)!=data_buffer||!gmj_display::decoded_admission(candidate,int64_t(candidate_data->nbuffer),declared)){++data_releases;++model_releases;error="Display decoded data budget mismatch";return false;}
    gmj_display::trace("data_created",declared,model_generation+1);
    model=candidate_owner.release();data=data_owner.release();model_path=path;++model_generation;resident_bytes=declared;serialized_bytes=bytes.size();
    render_shared.erase("model");bytes=PackedByteArray();gmj_display::trace("bridge_packet_unreferenced",0,model_generation);
    model->vis.quality.offsamples=0;model->vis.quality.shadowsize=std::min(model->vis.quality.shadowsize,1024);
    if(direct_fbo){model->vis.global.offwidth=16;model->vis.global.offheight=16;}
    mjv_defaultScene(&scene);mjv_makeScene(model,&scene,10000);
    mjr_defaultContext(&render);mjr_makeContext(model,&render,mjFONTSCALE_100);
    mjv_defaultOption(&options);mjv_defaultCamera(&camera);mjv_defaultFreeCamera(model,&camera);
    if(had_model)camera=previous_camera;
    options.flags[mjVIS_CONVEXHULL]=0;for(auto &group:options.geomgroup)group=1;
    scene.flags[mjRND_SHADOW]=0;scene.flags[mjRND_REFLECTION]=0;scene.flags[mjRND_SKYBOX]=0;scene.flags[mjRND_FOG]=0;
    reference_ids.clear();
    for(int i=0;i<reference_names.size();++i){int id=mj_name2id(model,mjOBJ_GEOM,reference_names[i].utf8().get_data());if(id<0){error="Comparison geom name missing";return false;}reference_ids.push_back(id);}
    fixture_camera=false;scene_ready=false;visible.clear();gmj_display::trace("gpu_created",resident_bytes,model_generation);return true;
  }
  void delete_slot(Slot &slot) {
    if(!matches(producer_binding())){++namespace_violations;fatal_context("refusing to delete a producer FBO in the wrong context");}
    if(slot.fbo)glDeleteFramebuffers(1,&slot.fbo);
    if(slot.depth)glDeleteRenderbuffers(1,&slot.depth);
    if(slot.texture&&glIsTexture(slot.texture))glDeleteTextures(1,&slot.texture);
    if(slot.texture)++releases;slot=Slot{};
  }

public:
  void render_frame(int width,int height,double dx,double dy,int action,bool running,bool reload,const String &path,double phase,int ui_serial,bool previous_visible) {
    if(frame==0)std::fprintf(stderr,"PROBE_STAGE render_enter\n");
    const auto begin=Clock::now();
    RenderingServer *rs=RenderingServer::get_singleton();
    const Binding entry=current_binding();
    if(!entry.context||!entry.display||!entry.draw||!entry.read)fatal_context("no valid Core entry binding");
    if(home.context&&!matches(home))fatal_context("render callback entered a foreign Core binding");
    ContextReturn guard{this,entry};
    if(!error.empty()){fail(error);return;}
    if(!compat&&!create_context()){fail(error);return;}
    if(frame==0)std::fprintf(stderr,"PROBE_STAGE context_created\n");
    GLXContext core=glXGetCurrentContext();
    if(!core||core==compat){fail("Unexpected Godot render context");return;}
    // This callback is queued after the previous engine draw and before this
    // frame's native writes. Unlike the main-thread post_draw signal it cannot
    // be overtaken by a newer producer callback. The final draw is drained once
    // explicitly during completion. Skip bootstrap/resize-invalid back buffers.
    const auto present_start=Clock::now();
    if(present_before_produce&&previous_visible&&current.width==width&&current.height==height)present_render({ui_serial-1,width,height});
    const auto present_end=Clock::now();
    const auto consumer_flush_start=Clock::now();
    GLsync consumed=fence("consume-fence");
    if(!consumed){if(!drain(entry))fatal_context("Core drain failed after fence error");fail("Consumer fence creation/flush failed");return;}
    const auto consumer_flushed=Clock::now();
    if(!checked_switch(producer_binding(),"activate-producer")){fail("Cannot activate producer GLX context");return;}
    const auto made_producer=Clock::now();
    if(!wait(consumed,"consume-wait")){fail("Consumer sync wait submission failed");return;}
    guard.dirty=true;
    const auto consumer_waited=Clock::now();
    if(compat_version.empty()){compat_version=reinterpret_cast<const char*>(glGetString(GL_VERSION));glGetIntegerv(GL_CONTEXT_PROFILE_MASK,&compat_profile);producer_release_behavior=release_behavior();glGenQueries(8,queries);glGenQueries(24,&timestamps[0][0]);}
    const auto context_in=Clock::now();
    bool loaded=true;
    if(!model||reload||model_path!=path.utf8().get_data()) loaded=load(path.utf8().get_data());
    if(!loaded){fail(error);return;}
    if(frame==0)std::fprintf(stderr,"PROBE_STAGE model_loaded\n");
    if(current.width!=width||current.height!=height) {
      if(current.texture)retired.push_back(current);
      current=Slot{};current.width=width;current.height=height;current.generation=++generation;
      glGenTextures(1,&current.texture);
      if(!current.texture){fail("Shared texture allocation failed");return;}
      ++allocations;max_live=std::max(max_live,allocations-releases);
      glBindTexture(GL_TEXTURE_2D,current.texture);
      glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
      glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,width,height,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);
      glGenFramebuffers(1,&current.fbo);glBindFramebuffer(GL_FRAMEBUFFER,current.fbo);
      glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,current.texture,0);
      if(direct_fbo){
        glGenRenderbuffers(1,&current.depth);glBindRenderbuffer(GL_RENDERBUFFER,current.depth);
        glRenderbufferStorage(GL_RENDERBUFFER,GL_DEPTH24_STENCIL8,width,height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_DEPTH_STENCIL_ATTACHMENT,GL_RENDERBUFFER,current.depth);
      }
      if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE){fail("Shared texture framebuffer is incomplete");return;}
    }
    if(!direct_fbo&&(render.offWidth!=width||render.offHeight!=height))mjr_resizeOffscreen(width,height,&render);
    const auto setup=Clock::now();
    // Consume the authoritative CPU scene. This replica is an asset owner only:
    // it never runs mj_forward, mj_step, or independent camera/picking logic.
    PackedFloat64Array state=render_shared.get("state",PackedFloat64Array());
    if(state.size()!=mj_stateSize(model,mjSTATE_INTEGRATION)){fail("Display state/model size mismatch");return;}
    mj_setState(model,data,state.ptr(),mjSTATE_INTEGRATION);
    if(state_audit)compare_state(state,false);
    const auto stepped=Clock::now();
    PackedByteArray geoms=render_shared.get("scene_geoms",PackedByteArray());
    PackedByteArray lights=render_shared.get("scene_lights",PackedByteArray());
    PackedByteArray cameras=render_shared.get("scene_cameras",PackedByteArray());
    PackedByteArray flags=render_shared.get("scene_flags",PackedByteArray());
    PackedByteArray visual=render_shared.get("scene_visual",PackedByteArray());
    PackedByteArray stat=render_shared.get("scene_stat",PackedByteArray());
    if(int(render_shared.get("scene_abi",0))!=mj_version()||geoms.size()%sizeof(mjvGeom)||geoms.size()>scene.maxgeom*int(sizeof(mjvGeom))||lights.size()%sizeof(mjvLight)||lights.size()>mjMAXLIGHT*int(sizeof(mjvLight))||cameras.size()!=sizeof(scene.camera)||flags.size()!=sizeof(scene.flags)||visual.size()!=sizeof(mjVisual)||stat.size()!=sizeof(mjStatistic)){fail("Invalid authoritative scene packet");return;}
    scene.ngeom=geoms.size()/sizeof(mjvGeom);scene.nlight=lights.size()/sizeof(mjvLight);
    if(!geoms.is_empty())std::memcpy(scene.geoms,geoms.ptr(),geoms.size());
    if(!lights.is_empty())std::memcpy(scene.lights,lights.ptr(),lights.size());
    std::memcpy(scene.camera,cameras.ptr(),cameras.size());std::memcpy(scene.flags,flags.ptr(),flags.size());
    // Context-sized GPU resources retain the admitted settings used by load().
    const auto quality=model->vis.quality;
    const int offwidth=model->vis.global.offwidth,offheight=model->vis.global.offheight;
    std::memcpy(&model->vis,visual.ptr(),visual.size());std::memcpy(&model->stat,stat.ptr(),stat.size());
    model->vis.quality=quality;model->vis.global.offwidth=offwidth;model->vis.global.offheight=offheight;
    scene.stereo=mjSTEREO_NONE;
    if(fixture_camera){
      auto c=base_camera;
      const double a=.25*std::sin(2*3.141592653589793*phase/12),co=std::cos(a),si=std::sin(a);
      auto rotate=[&](float *v,bool point){const double x=v[0]-(point?camera_center[0]:0),y=v[1]-(point?camera_center[1]:0);v[0]=float(co*x-si*y+(point?camera_center[0]:0));v[1]=float(si*x+co*y+(point?camera_center[1]:0));};
      rotate(c.pos,true);rotate(c.forward,false);rotate(c.up,false);scene.camera[0]=scene.camera[1]=c;
      for(int i=0;i<scene.nlight;++i)if(scene.lights[i].headlight)for(int k=0;k<3;++k){scene.lights[i].pos[k]=c.pos[k];scene.lights[i].dir[k]=c.forward[k];}
      int count=0;
      for(int i=0;i<scene.ngeom;++i){auto &g=scene.geoms[i];if(g.objtype==mjOBJ_GEOM&&(g.objid<0||g.objid>=int(visible.size())||!visible[g.objid]))continue;scene.geoms[count++]=g;}
      scene.ngeom=count;
    }
    if(reference_view){
      scene.camera[0]=scene.camera[1]=reference_camera;scene.nlight=0;
      int n=0;for(int i=0;i<scene.ngeom;++i){auto g=scene.geoms[i];
        if(g.objtype!=mjOBJ_GEOM||std::find(reference_ids.begin(),reference_ids.end(),g.objid)==reference_ids.end())continue;
        const char *name=mj_id2name(model,mjOBJ_GEOM,g.objid);const float color=name&&std::strstr(name,"floor")?.2f:.8f;
        for(int j=0;j<3;++j)g.rgba[j]=color;g.rgba[3]=1;g.emission=.7f;g.specular=0;g.reflectance=0;g.matid=-1;
        scene.geoms[n++]=g;
      }scene.ngeom=n;
    }
    scene_ready=true;
    const auto updated=Clock::now();
    const int query_slot=frame%8;
    if(query_pending[query_slot]){
      GLint ready=0;glGetQueryObjectiv(queries[query_slot],GL_QUERY_RESULT_AVAILABLE,&ready);
      if(ready){
        GLuint64 ns=0,t[3]{};glGetQueryObjectui64v(queries[query_slot],GL_QUERY_RESULT,&ns);gpu_ms=double(ns)/1e6;
        for(int k=0;k<3;++k)glGetQueryObjectui64v(timestamps[query_slot][k],GL_QUERY_RESULT,&t[k]);
        render_gpu_ms=double(t[1]-t[0])/1e6;blit_gpu_ms=double(t[2]-t[1])/1e6;
        ++gpu_samples;query_pending[query_slot]=false;
      }
    }
    const bool query=!query_pending[query_slot];
    if(query){glBeginQuery(GL_TIME_ELAPSED,queries[query_slot]);glQueryCounter(timestamps[query_slot][0],GL_TIMESTAMP);}
    if(direct_fbo){
      // Non-owning view of the public classic-renderer context. The owning
      // context keeps its original FBO IDs and is the ONLY one ever freed.
      // This bounded prototype covers offSamples=0 and the common-basic flags.
      mjrContext view=render;
      view.offFBO=current.fbo;view.offFBO_r=0;view.offSamples=0;
      view.offWidth=width;view.offHeight=height;view.currentBuffer=mjFB_OFFSCREEN;
      mjr_setBuffer(mjFB_OFFSCREEN,&view);mjr_render({0,0,width,height},&scene,&view);
    }else{
      mjr_setBuffer(mjFB_OFFSCREEN,&render);mjr_render({0,0,width,height},&scene,&render);
    }
    if(query)glQueryCounter(timestamps[query_slot][1],GL_TIMESTAMP);
    if(!direct_fbo){
      glBindFramebuffer(GL_READ_FRAMEBUFFER,render.offFBO);glBindFramebuffer(GL_DRAW_FRAMEBUFFER,current.fbo);
      // The copy also flips MuJoCo's bottom-left framebuffer for Godot's canvas.
      glBlitFramebuffer(0,0,width,height,0,height,width,0,GL_COLOR_BUFFER_BIT,GL_NEAREST);
    }
    if(query){glQueryCounter(timestamps[query_slot][2],GL_TIMESTAMP);glEndQuery(GL_TIME_ELAPSED);query_pending[query_slot]=true;}
    if(audit_present){
      // Diagnostic-only binary stripe, sampled from the real window back buffer.
      GLint scissor[4],draw_fbo=0;GLfloat color[4];GLboolean mask[4];
      const bool enabled=glIsEnabled(GL_SCISSOR_TEST);
      glGetIntegerv(GL_SCISSOR_BOX,scissor);glGetFloatv(GL_COLOR_CLEAR_VALUE,color);glGetBooleanv(GL_COLOR_WRITEMASK,mask);glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&draw_fbo);
      glBindFramebuffer(GL_DRAW_FRAMEBUFFER,current.fbo);glEnable(GL_SCISSOR_TEST);glColorMask(GL_TRUE,GL_TRUE,GL_TRUE,GL_TRUE);
      for(int bit=0;bit<26;++bit){glScissor(width-32+bit,16,1,1);glClearColor(bit<24?float((unsigned(frame+1)>>bit)&1):0,bit==24?1:0,bit==25?1:0,1);glClear(GL_COLOR_BUFFER_BIT);}
      glClearColor(color[0],color[1],color[2],color[3]);glColorMask(mask[0],mask[1],mask[2],mask[3]);glScissor(scissor[0],scissor[1],scissor[2],scissor[3]);if(!enabled)glDisable(GL_SCISSOR_TEST);glBindFramebuffer(GL_DRAW_FRAMEBUFFER,draw_fbo);
    }
    check_errors();
    const auto producer_flush_start=Clock::now();
    GLsync produced=fence("produce-fence");
    if(!produced){fail("Producer fence creation/flush failed");return;}
    const auto produced_at=Clock::now();
    if(inject("restore-permanent")){permanent_restore_failure=true;++context_failures;fail("Injected permanent Core restoration failure");return;}
    if(!checked_switch(entry,"restore-core")){fail("Cannot restore Godot Core context");return;}
    const auto made_consumer=Clock::now();
    if(!wait(produced,"produce-wait")){fail("Producer sync wait submission failed");return;}
    guard.dirty=false;
    const auto producer_waited=Clock::now();
    if(frame==0)std::fprintf(stderr,"PROBE_STAGE produced\n");
    if(!current.rid.is_valid()) {
      if(!glIsTexture(current.texture)){fail("Producer texture is not shared with Godot");return;}
      ++shared_checks;
      current.rid=rs->texture_create_from_native_handle(RenderingServer::TEXTURE_TYPE_2D,Image::FORMAT_RGBA8,current.texture,width,height,1);
      if(frame==0)std::fprintf(stderr,"PROBE_STAGE imported\n");
      if(!current.rid.is_valid()){fail("Godot native texture import failed");return;}
    }
    int ack=0;{std::lock_guard<std::mutex> lock(mutex);ack=acknowledged;}
    bool deletable=false;
    for(auto &slot:retired)if(slot.generation<ack){if(slot.rid.is_valid()){rs->free_rid(slot.rid);slot.rid=RID();}deletable=true;}
    if(deletable){
      GLsync safe=fence("retire-fence");
      if(!safe){if(!drain(entry))fatal_context("retirement Core drain failed");fail("Retirement fence failed");return;}
      if(!checked_switch(producer_binding(),"retire-enter")){fail("Retirement context activation failed");return;}
      if(!wait(safe,"retire-wait")){fail("Retirement wait failed");return;}
      guard.dirty=true;
      for(auto it=retired.begin();it!=retired.end();){if(it->generation<ack){delete_slot(*it);it=retired.erase(it);}else ++it;}
      glFlush();
      if(!checked_switch(entry,"retire-restore")){fail("Retirement Core restoration failed");return;}
      guard.dirty=false;
    }
    check_errors();
    const auto end=Clock::now();
    Dictionary d;
    d["viewer_frame_id"]=render_shared.get("frame_id",0);d["viewer_revision"]=render_shared.get("revision",-1);d["authoritative_scene"]=true;d["texture"]=current.rid;d["width"]=width;d["height"]=height;d["generation"]=generation;d["frame"]=++frame;
    d["shared_revision"]=render_shared["revision"];d["shared_space"]=render_shared["space"];
    double qsum=0;for(int i=0;i<model->nq;++i)qsum+=(i+1)*data->qpos[i];d["qpos_checksum"]=qsum;
    d["stepping_policy"]="restore_then_forward";d["reference_view"]=reference_view;d["reference_geom_count"]=int(reference_ids.size());
    d["model_generation"]=model_generation;d["nq"]=int(model->nq);d["ngeom"]=int(model->ngeom);d["time"]=data->time;
    d["core_version"]=String(core_version.c_str());d["compat_version"]=String(compat_version.c_str());d["renderer"]=String(renderer.c_str());d["vendor"]=String(vendor.c_str());
    d["core_profile"]=core_profile;d["compat_profile"]=compat_profile;
    d["total_cpu_ms"]=elapsed(begin,end);d["context_in_ms"]=elapsed(begin,context_in);d["setup_ms"]=elapsed(context_in,setup);
    d["step_ms"]=elapsed(setup,stepped);d["scene_ms"]=elapsed(stepped,updated);d["render_blit_cpu_ms"]=elapsed(updated,produced_at);d["return_import_ms"]=elapsed(produced_at,end);
    d["allocations"]=allocations;d["releases"]=releases;d["live_textures"]=allocations-releases;d["max_live_textures"]=max_live;d["shared_checks"]=shared_checks;d["gl_errors"]=gl_errors;
    d["camera_azimuth"]=camera.azimuth;d["camera_elevation"]=camera.elevation;d["camera_distance"]=camera.distance;
    d["camera_lookat_x"]=camera.lookat[0];d["camera_lookat_y"]=camera.lookat[1];d["camera_lookat_z"]=camera.lookat[2];
    d["camera_transfer_error"]=camera_transfer_error;
    d["render_blit_gpu_ms"]=gpu_ms;d["gpu_samples"]=gpu_samples;
    d["mujoco_render_gpu_ms"]=render_gpu_ms;d["blit_gpu_ms"]=blit_gpu_ms;d["direct_fbo"]=direct_fbo;
    if(viewport.is_valid()){
      d["godot_render_cpu_ms"]=rs->viewport_get_measured_render_time_cpu(viewport);
      d["godot_render_gpu_ms"]=rs->viewport_get_measured_render_time_gpu(viewport);
    }
    d["fixture_camera"]=fixture_camera;d["scene_ngeom"]=scene.ngeom;
    d["presentation_swaps"]=presentation_swaps;d["presentation_errors"]=presentation_errors;d["presentation_cpu_ms"]=presentation_cpu_ms;
    d["presentation_native_frame"]=presentation_native_frame;d["presentation_ui_serial"]=presentation_ui_serial;d["presentation_completed_usec"]=presentation_completed_usec;
    d["consumer_fence_flush_ms"]=elapsed(consumer_flush_start,consumer_flushed);d["make_producer_ms"]=elapsed(consumer_flushed,made_producer);d["consumer_wait_submit_ms"]=elapsed(made_producer,consumer_waited);
    d["producer_fence_flush_ms"]=elapsed(producer_flush_start,produced_at);d["make_consumer_ms"]=elapsed(produced_at,made_consumer);d["producer_wait_submit_ms"]=elapsed(made_consumer,producer_waited);
    d["core_release_behavior"]=core_release_behavior;d["producer_release_behavior"]=producer_release_behavior;d["release_none_requested"]=release_none;d["presentation_drain_ms"]=presentation_drain_ms;
    d["prior_presentation_ms"]=elapsed(present_start,present_end);d["native_work_cpu_ms"]=elapsed(present_end,end);
    status(d);publish(d);
    if(frame==1)std::fprintf(stderr,"PROBE_STAGE published\n");
  }
  int request(int width,int height,double dx,double dy,int action,bool running,bool reload,const String &path,double phase,int ui_serial,bool previous_visible) {
    width=std::clamp(width,16,4096);height=std::clamp(height,16,4096);
    int ticket=0;
    {std::lock_guard<std::mutex> lock(mutex);if(pending||closed||terminal_failure)return 0;pending=true;ticket=frame+1;queued={width,height,action,dx,dy,running,reload,path,phase,ui_serial,previous_visible};}
    RenderingServer::get_singleton()->call_on_render_thread(callable_mp(this,&MjSharedNativeViewBridge::render_queued));
    return ticket;
  }
  // Frozen before the first submission; diagnostic flat-material comparison,
  // not a replacement for interactive native-camera controls.
  bool configure_comparison(const PackedFloat64Array &values,const PackedStringArray &names) {
    if(!main_thread()||values.size()!=12||names.is_empty()||names.size()>9000)return false;
    for(int i=0;i<12;++i)if(!std::isfinite(values[i]))return false;
    if(values[9]<=0||values[10]<=values[9]||values[11]<=1||values[11]>=170)return false;
    std::lock_guard<std::mutex> lock(mutex);if(pending||frame||model||closed)return false;
    for(int j=0;j<3;++j){reference_camera.pos[j]=values[j];reference_camera.forward[j]=values[3+j];reference_camera.up[j]=values[6+j];}
    reference_camera.frustum_near=values[9];reference_camera.frustum_far=values[10];reference_camera.frustum_top=values[9]*std::tan(values[11]*3.141592653589793/360);reference_camera.frustum_bottom=-reference_camera.frustum_top;
    reference_names=names;reference_view=true;return true;
  }
  bool acquire_transport() {
    if(!main_thread())return false;
    std::lock_guard<std::mutex> lock(mutex);if(closed||terminal_failure)return false;
    void *expected=nullptr;return display_owner.compare_exchange_strong(expected,this)||expected==this;
  }
  bool ready_for_request() {
    std::lock_guard<std::mutex> lock(mutex);return !pending&&!closed&&!terminal_failure&&display_owner.load()==this;
  }
  int request_shared(const Dictionary &packet,int width,int height,double dx,double dy,int action) {
    if(!main_thread()||Engine::get_singleton()->is_editor_hint())return 0;
    if(!packet.has("space")||!packet.has("revision")||!packet.has("state")||!packet.has("scene_geoms"))return 0;
    PackedFloat64Array state=packet["state"];
    if(state.size()>1048576||!std::isfinite(dx)||!std::isfinite(dy)||action>mjMOUSE_ZOOM||action < -1)return 0;
    for(int i=0;i<state.size();++i)if(!std::isfinite(state[i]))return 0;
    const String token=String::num_int64(int64_t(packet["space"]))+"/"+String::num_int64(int64_t(packet["revision"]));
    int ticket=0;
    {std::lock_guard<std::mutex> lock(mutex);if(pending||closed||terminal_failure)return 0;
     if(display_owner.load()!=this){published["error"]="Native display memory lease is required";terminal_failure=true;return 0;}
     pending=true;ticket=frame+1;replace_dictionary(queued_shared,packet.duplicate(true));
     if(packet.has("model")){PackedByteArray a=packet["model"],b=queued_shared["model"];shared_buffer_identity=shared_buffer_identity&&(a.ptr()==b.ptr());++serialized_payloads;}

     queued={std::clamp(width,16,4096),std::clamp(height,16,4096),action,dx,dy,false,false,token,0.0,0,false};}
    RenderingServer::get_singleton()->call_on_render_thread(callable_mp(this,&MjSharedNativeViewBridge::render_queued));return ticket;
  }
  void render_queued() {
    Request value;
    {std::lock_guard<std::mutex> lock(mutex);value=queued;render_shared=queued_shared;replace_dictionary(queued_shared,Dictionary());}
    render_frame(value.width,value.height,value.dx,value.dy,value.action,value.running,value.reload,value.path,value.phase,value.ui_serial,value.previous_visible);
    replace_dictionary(render_shared,Dictionary());
  }
  Dictionary diagnostic_allocator(bool trim) {
    Dictionary out;if(!main_thread()||!std::getenv("GMJ_DIAGNOSTIC_MEMORY"))return out;
    auto stats=[](){auto a=mallinfo2();Dictionary d;d["arena"]=int64_t(a.arena);d["allocated"]=int64_t(a.uordblks);d["free"]=int64_t(a.fordblks);d["mapped"]=int64_t(a.hblkhd);d["mapped_blocks"]=int64_t(a.hblks);return d;};
    out["before"]=stats();if(trim)out["trim_result"]=malloc_trim(0);out["after"]=stats();return out;
  }
  Dictionary snapshot() { std::lock_guard<std::mutex> lock(mutex); return published.duplicate(); }
  bool main_thread() const {return OS::get_singleton()->get_thread_caller_id()==OS::get_singleton()->get_main_thread_id();}
  void acknowledge_render(int value) {std::lock_guard<std::mutex> lock(mutex);acknowledged=std::max(acknowledged,value);}
  void acknowledge(int value) {
    if(!main_thread())return;
    {std::lock_guard<std::mutex> lock(mutex);if(closed)return;}
    // Ordered after canvas replacement, never an immediate cross-thread retirement permission.
    RenderingServer::get_singleton()->call_on_render_thread(callable_mp(this,&MjSharedNativeViewBridge::acknowledge_render).bind(value));
  }
  void configure_viewport(const RID &value,bool direct) {
    if(!main_thread())return;
    viewport=value;direct_fbo=direct;
    RenderingServer::get_singleton()->viewport_set_measure_render_time(viewport,true);
  }
  void configure_fault(const String &point,int at,const String &output){if(!main_thread())return;fault_point=point;fault_at=std::max(1,at);fault_output=output;}
  void configure_handoff(bool audit,bool drain,bool no_release_flush,bool before_produce){audit_present=audit;drain_present=drain;release_none=no_release_flush;present_before_produce=before_produce;}
  // The engine's direct-to-screen branch skips gl_end_frame in this version.
  // This single-window GLX probe owns that missing swap, AFTER canvas drawing.
  // Never use this with an engine that also swaps the direct viewport.
  void bind_presentation_render() {
    Dictionary result;
    presentation_context=glXGetCurrentContext();presentation_display=glXGetCurrentDisplay();
    GLint profile=0;GLboolean double_buffer=GL_FALSE;
    if(presentation_context){glGetIntegerv(GL_CONTEXT_PROFILE_MASK,&profile);glGetBooleanv(GL_DOUBLEBUFFER,&double_buffer);}
    const bool valid=presentation_context&&presentation_display&&presentation_context!=compat&&glXGetCurrentDrawable()==presentation_window&&glXGetCurrentReadDrawable()==presentation_window&&profile==GL_CONTEXT_CORE_PROFILE_BIT&&double_buffer;
    result["ok"]=valid;result["drawable"]=int64_t(glXGetCurrentDrawable());result["profile"]=profile;result["double_buffer"]=bool(double_buffer);
    result["render_thread"]=int64_t(godot::OS::get_singleton()->get_thread_caller_id());
    if(!valid){result["error"]="Direct presentation requires the original double-buffered Core context and owned X11 draw/read window";presentation_context=nullptr;presentation_display=nullptr;}
    std::lock_guard<std::mutex> lock(mutex);presentation_binding=result;
  }
  Dictionary configure_presentation(int64_t window) {
    if(!main_thread()){Dictionary d;d["error"]="Main-thread configuration required";return d;}
    presentation_window=GLXDrawable(window);
    auto rs=RenderingServer::get_singleton();rs->call_on_render_thread(callable_mp(this,&MjSharedNativeViewBridge::bind_presentation_render));rs->force_sync();
    std::lock_guard<std::mutex> lock(mutex);return presentation_binding.duplicate();
  }
  bool valid_presentation_context() const {
    return presentation_window&&presentation_context&&glXGetCurrentContext()==presentation_context&&glXGetCurrentDisplay()==presentation_display&&glXGetCurrentDrawable()==presentation_window&&glXGetCurrentReadDrawable()==presentation_window;
  }
  void present_render(const PresentRequest &value) {
    if(terminal_failure)return;
    auto begin=Clock::now();
    if(!valid_presentation_context()){
      ++presentation_errors;
    }else{
      if(audit_present&&value.width>64&&value.height>64){
        GLint previous=0,read_buffer=0,pack=0,row_length=0,skip_rows=0,skip_pixels=0,pbo=0;
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&previous);glGetIntegerv(GL_PACK_ALIGNMENT,&pack);glGetIntegerv(GL_PACK_ROW_LENGTH,&row_length);glGetIntegerv(GL_PACK_SKIP_ROWS,&skip_rows);glGetIntegerv(GL_PACK_SKIP_PIXELS,&skip_pixels);glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING,&pbo);
        glBindFramebuffer(GL_READ_FRAMEBUFFER,0);glGetIntegerv(GL_READ_BUFFER,&read_buffer);glReadBuffer(GL_BACK);glBindBuffer(GL_PIXEL_PACK_BUFFER,0);glPixelStorei(GL_PACK_ALIGNMENT,1);glPixelStorei(GL_PACK_ROW_LENGTH,0);glPixelStorei(GL_PACK_SKIP_ROWS,0);glPixelStorei(GL_PACK_SKIP_PIXELS,0);
        unsigned char pixels[2][26*3]{};
        glReadPixels(value.width-32,16,26,1,GL_RGB,GL_UNSIGNED_BYTE,pixels[0]);
        glReadPixels(value.width-32,value.height-17,26,1,GL_RGB,GL_UNSIGNED_BYTE,pixels[1]);presentation_readbacks+=2;
        auto decode=[](const unsigned char *p){unsigned serial=0;for(int i=0;i<24;++i)if(p[i*3]>127)serial|=1u<<i;return serial;};
        auto valid=[](const unsigned char *p,bool native){return p[24*3]<10&&p[25*3]<10&&(native?(p[24*3+1]>245&&p[24*3+2]<10&&p[25*3+1]<10&&p[25*3+2]>245):(p[24*3+1]<10&&p[24*3+2]>245&&p[25*3+1]>245&&p[25*3+2]<10));};
        const int native=decode(pixels[0]),ui=decode(pixels[1]);const bool markers=valid(pixels[0],true)&&valid(pixels[1],false);
        if(!markers)++presentation_bad_markers;
        if(ui!=value.serial)++presentation_ui_mismatch;
        if(native!=frame)++presentation_native_mismatch;
        if(presentation_trace.size()<512||((!markers||ui!=value.serial||native!=frame)&&presentation_trace.size()<1024)){Dictionary entry;entry["expected_ui"]=value.serial;entry["actual_ui"]=ui;entry["latest_native"]=frame;entry["actual_native"]=native;entry["markers_valid"]=markers;presentation_trace.append(entry);}
        glReadBuffer(read_buffer);glBindFramebuffer(GL_READ_FRAMEBUFFER,previous);glPixelStorei(GL_PACK_ALIGNMENT,pack);glPixelStorei(GL_PACK_ROW_LENGTH,row_length);glPixelStorei(GL_PACK_SKIP_ROWS,skip_rows);glPixelStorei(GL_PACK_SKIP_PIXELS,skip_pixels);glBindBuffer(GL_PIXEL_PACK_BUFFER,pbo);
        check_errors();
      }
      auto drain_start=Clock::now();if(drain_present)glFinish();presentation_drain_ms=elapsed(drain_start,Clock::now());
      const auto swap_begin=Clock::now();glXSwapBuffers(presentation_display,presentation_window);++presentation_swaps;
      presentation_cpu_ms=elapsed(swap_begin,Clock::now());
      presentation_native_frame=frame;presentation_ui_serial=value.serial;presentation_completed_usec=godot::Time::get_singleton()->get_ticks_usec();
    }
    (void)begin;
  }
  void present_queued() {
    PresentRequest value;
    {std::lock_guard<std::mutex> lock(mutex);if(presentation_queue.empty())return;value=presentation_queue.front();presentation_queue.pop_front();}
    present_render(value);
  }
  void present_window(int serial,int width,int height) {
    {std::lock_guard<std::mutex> lock(mutex);if(closed||terminal_failure)return;presentation_queue.push_back({serial,width,height});}
    RenderingServer::get_singleton()->call_on_render_thread(callable_mp(this,&MjSharedNativeViewBridge::present_queued));
  }
  void capture_render() {
    Dictionary result;
    if(!valid_presentation_context()){
      result["error"]="No current window GLX context for validation capture";
    }else{
      GLint previous=0,window_read=0,pack=0,row_length=0,skip_rows=0,skip_pixels=0,pbo=0;
      GLint original_pack[5]{};GLuint scratch=0;
      if(audit_present){
        glGetIntegerv(GL_PACK_ALIGNMENT,&original_pack[0]);glGetIntegerv(GL_PACK_ROW_LENGTH,&original_pack[1]);glGetIntegerv(GL_PACK_SKIP_ROWS,&original_pack[2]);glGetIntegerv(GL_PACK_SKIP_PIXELS,&original_pack[3]);glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING,&original_pack[4]);
        glGenBuffers(1,&scratch);glBindBuffer(GL_PIXEL_PACK_BUFFER,scratch);glBufferData(GL_PIXEL_PACK_BUFFER,16,nullptr,GL_STREAM_READ);glPixelStorei(GL_PACK_ALIGNMENT,8);glPixelStorei(GL_PACK_ROW_LENGTH,7);glPixelStorei(GL_PACK_SKIP_ROWS,2);glPixelStorei(GL_PACK_SKIP_PIXELS,3);
      }
      glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&previous);
      glGetIntegerv(GL_PACK_ALIGNMENT,&pack);
      glGetIntegerv(GL_PACK_ROW_LENGTH,&row_length);glGetIntegerv(GL_PACK_SKIP_ROWS,&skip_rows);glGetIntegerv(GL_PACK_SKIP_PIXELS,&skip_pixels);glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING,&pbo);
      glBindFramebuffer(GL_READ_FRAMEBUFFER,0);
      glGetIntegerv(GL_READ_BUFFER,&window_read);
      result["drawable"]=int64_t(glXGetCurrentDrawable());
      glReadBuffer(GL_FRONT);glPixelStorei(GL_PACK_ALIGNMENT,1);
      glBindBuffer(GL_PIXEL_PACK_BUFFER,0);glPixelStorei(GL_PACK_ROW_LENGTH,0);glPixelStorei(GL_PACK_SKIP_ROWS,0);glPixelStorei(GL_PACK_SKIP_PIXELS,0);
      std::vector<unsigned char> pixels(size_t(capture_width)*capture_height*3);
      glReadPixels(0,0,capture_width,capture_height,GL_RGB,GL_UNSIGNED_BYTE,pixels.data());
      const GLenum problem=glGetError();
      glReadBuffer(window_read);glBindFramebuffer(GL_READ_FRAMEBUFFER,previous);glPixelStorei(GL_PACK_ALIGNMENT,pack);
      glPixelStorei(GL_PACK_ROW_LENGTH,row_length);glPixelStorei(GL_PACK_SKIP_ROWS,skip_rows);glPixelStorei(GL_PACK_SKIP_PIXELS,skip_pixels);glBindBuffer(GL_PIXEL_PACK_BUFFER,pbo);
      if(audit_present){
        GLint actual[5]{};glGetIntegerv(GL_PACK_ALIGNMENT,&actual[0]);glGetIntegerv(GL_PACK_ROW_LENGTH,&actual[1]);glGetIntegerv(GL_PACK_SKIP_ROWS,&actual[2]);glGetIntegerv(GL_PACK_SKIP_PIXELS,&actual[3]);glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING,&actual[4]);
        result["poisoned_pack_state_restored"] = actual[0]==8&&actual[1]==7&&actual[2]==2&&actual[3]==3&&actual[4]==int(scratch);
        glPixelStorei(GL_PACK_ALIGNMENT,original_pack[0]);glPixelStorei(GL_PACK_ROW_LENGTH,original_pack[1]);glPixelStorei(GL_PACK_SKIP_ROWS,original_pack[2]);glPixelStorei(GL_PACK_SKIP_PIXELS,original_pack[3]);glBindBuffer(GL_PIXEL_PACK_BUFFER,original_pack[4]);glDeleteBuffers(1,&scratch);
      }
      result["gl_error"]=int(problem);
      if(problem==GL_NO_ERROR){
        std::ofstream file(capture_path.utf8().get_data(),std::ios::binary);
        file<<"P6\n"<<capture_width<<" "<<capture_height<<"\n255\n";
        for(int y=capture_height-1;y>=0;--y)file.write(reinterpret_cast<char*>(pixels.data()+size_t(y)*capture_width*3),capture_width*3);
        result["ok"]=bool(file);result["width"]=capture_width;result["height"]=capture_height;
      }else result["error"]="Window front-buffer validation read failed";
    }
    std::lock_guard<std::mutex> lock(mutex);capture_result=result;
  }
  Dictionary capture_window(const String &path,int width,int height) {
    if(!main_thread()){Dictionary d;d["error"]="Main-thread capture required";return d;}
    if(width<16||height<16||width>8192||height>8192){Dictionary result;result["error"]="Invalid capture dimensions";return result;}
    capture_path=path;capture_width=width;capture_height=height;
    auto rs=RenderingServer::get_singleton();rs->call_on_render_thread(callable_mp(this,&MjSharedNativeViewBridge::capture_render));rs->force_sync();
    std::lock_guard<std::mutex> lock(mutex);return capture_result.duplicate();
  }
  void release_render() {
    const Binding entry=current_binding();
    if(!entry.context||!entry.display)fatal_context("cleanup has no Core entry binding");
    ContextReturn guard{this,entry};
    RenderingServer *rs=RenderingServer::get_singleton();
    if(home.context&&!matches(home)&&!checked_switch(home,"cleanup-core"))fatal_context("cleanup cannot activate the owning Core context");
    if(current.rid.is_valid()){rs->free_rid(current.rid);current.rid=RID();}
    for(auto &slot:retired)if(slot.rid.is_valid()){rs->free_rid(slot.rid);slot.rid=RID();}
    if(compat&&pbuffer){
      const Binding core=current_binding();
      GLsync consumed=fence("cleanup-fence");
      if(!consumed&&!drain(core))fatal_context("cleanup Core fence/drain failed");
      if(!checked_switch(producer_binding(),"cleanup-enter")&&!checked_switch(producer_binding(),"cleanup-enter-retry"))fatal_context("cleanup cannot activate producer");
      if(consumed&&!wait(consumed,"cleanup-wait")){
        if(!checked_switch(core,"cleanup-drain-core")||!drain(core)||!checked_switch(producer_binding(),"cleanup-drain-producer"))fatal_context("cleanup wait recovery failed");
      }
      guard.dirty=true;
      if(current.texture)delete_slot(current);
      for(auto &slot:retired)delete_slot(slot);
      retired.clear();
      glDeleteQueries(8,queries);glDeleteQueries(24,&timestamps[0][0]);
      release_model();
      if(!drain(producer_binding()))fatal_context("cleanup producer drain failed");
      for(GLsync sync:live_syncs){glDeleteSync(sync);}
      live_syncs.clear();
      glFlush();
      if(!checked_switch(core,"cleanup-restore"))restore_or_exit(core,false);
      guard.dirty=false;
    }
    if(compat){if(pbuffer)glXDestroyPbuffer(display,pbuffer);glXDestroyContext(display,compat);compat=nullptr;pbuffer=0;}
    restore_or_exit(entry,false);
    cleanup_complete=true;
    replace_dictionary(queued_shared,Dictionary());replace_dictionary(render_shared,Dictionary());void* owner=this;display_owner.compare_exchange_strong(owner,nullptr);
    Dictionary d=snapshot();d.erase("texture");d["closed"]=true;d["live_textures"]=allocations-releases;d["allocations"]=allocations;d["releases"]=releases;d["gl_errors"]=gl_errors;
    d["presentation_swaps"]=presentation_swaps;d["presentation_errors"]=presentation_errors;d["presentation_binding"]=presentation_binding;d["presentation_readbacks"]=presentation_readbacks;d["presentation_bad_markers"]=presentation_bad_markers;d["presentation_ui_mismatch"]=presentation_ui_mismatch;d["presentation_native_mismatch"]=presentation_native_mismatch;d["presentation_trace"]=presentation_trace;
    status(d);publish(d);
  }
  Dictionary finish() {
    if(!main_thread()){Dictionary d;d["error"]="Main-thread stop required";return d;}
    {std::lock_guard<std::mutex> lock(mutex);if(closed)return published;closed=true;}
    auto rs=RenderingServer::get_singleton();rs->call_on_render_thread(callable_mp(this,&MjSharedNativeViewBridge::release_render));rs->force_sync();
    return snapshot();
  }
protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("configure_comparison","camera","names"),&MjSharedNativeViewBridge::configure_comparison);
    ClassDB::bind_method(D_METHOD("acquire_transport"),&MjSharedNativeViewBridge::acquire_transport);
    ClassDB::bind_method(D_METHOD("ready_for_request"),&MjSharedNativeViewBridge::ready_for_request);
    ClassDB::bind_method(D_METHOD("diagnostic_allocator","trim"),&MjSharedNativeViewBridge::diagnostic_allocator);
    ClassDB::bind_method(D_METHOD("request_shared","packet","width","height","dx","dy","action"),&MjSharedNativeViewBridge::request_shared);
    ClassDB::bind_method(D_METHOD("snapshot"),&MjSharedNativeViewBridge::snapshot);
    ClassDB::bind_method(D_METHOD("acknowledge","generation"),&MjSharedNativeViewBridge::acknowledge);
    ClassDB::bind_method(D_METHOD("finish"),&MjSharedNativeViewBridge::finish);
    ClassDB::bind_method(D_METHOD("configure_viewport","viewport","direct_fbo"),&MjSharedNativeViewBridge::configure_viewport);
    ClassDB::bind_method(D_METHOD("configure_fault","point","occurrence","output"),&MjSharedNativeViewBridge::configure_fault);
    ClassDB::bind_method(D_METHOD("capture_window","path","width","height"),&MjSharedNativeViewBridge::capture_window);
    ClassDB::bind_method(D_METHOD("configure_presentation","window"),&MjSharedNativeViewBridge::configure_presentation);
  }
};

static void initialize(ModuleInitializationLevel level){if(level==MODULE_INITIALIZATION_LEVEL_SCENE)ClassDB::register_class<MjSharedNativeViewBridge>();}
extern "C" GDExtensionBool GDE_EXPORT gmj_shared_native_view_init(GDExtensionInterfaceGetProcAddress proc,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization) {
  GDExtensionBinding::InitObject init(proc,library,initialization);init.register_initializer(initialize);init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);return init.init();
}
