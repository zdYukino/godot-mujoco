// Standalone native viewer using the official mjv_updateScene/mjr_render path
// (the same rendering calls as MuJoCo's basic/simulate). No second simulation,
// Python wrapper, image readback or embedded Godot renderer in the timed loop.
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>
#include <GL/glx.h>
#include <X11/Xlib.h>
#include <mujoco/mujoco.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cctype>
#include <cmath>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using Clock=std::chrono::steady_clock;
static double seconds(Clock::time_point a,Clock::time_point b){return std::chrono::duration<double>(b-a).count();}
static std::string quote(const char*s){std::string out="\"";for(;s&&*s;++s){if(*s=='"'||*s=='\\')out+='\\';if(*s>=' ')out+=*s;}return out+'"';}
static void restore(const mjModel*m,mjData*d,const std::vector<double>&s){mj_resetData(m,d);mj_setState(m,d,s.data(),mjSTATE_INTEGRATION);mj_forward(m,d);}
static void write_state(const std::string&path,const mjModel*m,const mjData*d){std::vector<double>s(mj_stateSize(m,mjSTATE_INTEGRATION));mj_getState(m,d,s.data(),mjSTATE_INTEGRATION);std::ofstream f(path,std::ios::binary);f.write(reinterpret_cast<char*>(s.data()),s.size()*sizeof(double));}
static int warnings(const mjData*d){int n=0;for(int i=0;i<mjNWARNING;++i)n+=d->warning[i].number;return n;}

struct NativeWindow {
 Display *display=nullptr;::Window window=0;GLXContext context=nullptr;
 NativeWindow(int width,int height){
  display=XOpenDisplay(nullptr);if(!display)throw std::runtime_error("Cannot open the real X display");
  int attrs[]={GLX_RGBA,GLX_DOUBLEBUFFER,GLX_DEPTH_SIZE,24,None};
  XVisualInfo*visual=glXChooseVisual(display,DefaultScreen(display),attrs);
  if(!visual)throw std::runtime_error("No double-buffered GLX visual");
  XSetWindowAttributes wa{};wa.colormap=XCreateColormap(display,RootWindow(display,visual->screen),visual->visual,AllocNone);
  wa.override_redirect=True;
  wa.event_mask=StructureNotifyMask;
  window=XCreateWindow(display,RootWindow(display,visual->screen),0,0,width,height,0,visual->depth,InputOutput,visual->visual,CWColormap|CWEventMask|CWOverrideRedirect,&wa);
  XStoreName(display,window,"MuJoCo native renderer benchmark");
  context=glXCreateContext(display,visual,nullptr,True);XFree(visual);
  XMapRaised(display,window);XSync(display,False);
  if(!context||!glXMakeCurrent(display,window,context))throw std::runtime_error("Cannot make GLX context current");
  auto ext=reinterpret_cast<PFNGLXSWAPINTERVALEXTPROC>(glXGetProcAddressARB(reinterpret_cast<const GLubyte*>("glXSwapIntervalEXT")));
  if(ext)ext(display,window,0);
  else {auto mesa=reinterpret_cast<PFNGLXSWAPINTERVALMESAPROC>(glXGetProcAddressARB(reinterpret_cast<const GLubyte*>("glXSwapIntervalMESA")));if(mesa)mesa(0);}
 }
 ~NativeWindow(){if(display){glXMakeCurrent(display,None,nullptr);if(context)glXDestroyContext(display,context);if(window)XDestroyWindow(display,window);XCloseDisplay(display);}}
 void poll(){while(XPending(display)){XEvent event;XNextEvent(display,&event);}}
 void check_size(int w,int h){XWindowAttributes a;XGetWindowAttributes(display,window,&a);if(a.width!=w||a.height!=h)throw std::runtime_error("Window manager changed the native 3D viewport dimensions");}
};

struct Camera {
 mjvGLCamera base{};std::array<double,3> center{};
 explicit Camera(const std::string&path){std::ifstream f(path);for(float&v:base.pos)f>>v;for(float&v:base.forward)f>>v;for(float&v:base.up)f>>v;for(double&v:center)f>>v;f>>base.frustum_near>>base.frustum_far>>base.frustum_top;base.frustum_bottom=-base.frustum_top;base.frustum_center=0;base.orthographic=0;if(!f)throw std::runtime_error("Invalid camera fixture");}
 mjvGLCamera at(double t)const{
  auto camera=base;double a=.25*std::sin(2*3.141592653589793*t/12),c=std::cos(a),s=std::sin(a);
  auto rotate=[&](float*v,bool point){double x=v[0]-(point?center[0]:0),y=v[1]-(point?center[1]:0);v[0]=float(c*x-s*y+(point?center[0]:0));v[1]=float(s*x+c*y+(point?center[1]:0));};
  rotate(camera.pos,true);rotate(camera.forward,false);rotate(camera.up,false);return camera;
 }
};

struct Frame {double frame_ms=0,step_ms=0,scene_ms=0,render_cpu_ms=0,swap_ms=0,gpu_ms=-1,time=0;int ncon=0;};
struct Queries {
 static constexpr int count=128;GLuint id[count]{};int frame[count]{};bool active[count]{};
 Queries(){glGenQueries(count,id);}
 ~Queries(){glDeleteQueries(count,id);}
 void retrieve(int slot,std::vector<Frame>&rows){if(!active[slot])return;GLint ready=0;glGetQueryObjectiv(id[slot],GL_QUERY_RESULT_AVAILABLE,&ready);if(!ready)return;GLuint64 ns=0;glGetQueryObjectui64v(id[slot],GL_QUERY_RESULT,&ns);if(frame[slot]>=0&&frame[slot]<int(rows.size()))rows[frame[slot]].gpu_ms=double(ns)/1e6;active[slot]=false;}
};

int main(int argc,char**argv)try{
 if(argc!=13)throw std::runtime_error("usage: native model.mjb state.f64 camera.txt visible.txt output-prefix mode profile warmup sample steps width height");
 const std::string prefix=argv[5],mode=argv[6],profile=argv[7];
 double warmup=std::stod(argv[8]),sample=std::stod(argv[9]);int steps=std::stoi(argv[10]),width=std::stoi(argv[11]),height=std::stoi(argv[12]);
 auto*m=mj_loadModel(argv[1],nullptr);if(!m)throw std::runtime_error("Cannot load compiled fixture model");auto*d=mj_makeData(m);
 Dl_info library{};dladdr(reinterpret_cast<void*>(mj_versionString),&library);
 std::vector<double>state(mj_stateSize(m,mjSTATE_INTEGRATION));std::ifstream f(argv[2],std::ios::binary);f.read(reinterpret_cast<char*>(state.data()),state.size()*sizeof(double));if(!f||f.peek()!=EOF)throw std::runtime_error("State ABI/length mismatch");restore(m,d,state);
 if(mode=="physics") {
  // Short unmeasured warmup then reset, so both sides time the same trajectory.
  for(int i=0;i<std::min(1000,steps);++i)mj_step(m,d);restore(m,d,state);
  auto start=Clock::now();for(int i=0;i<steps;++i)mj_step(m,d);double elapsed=seconds(start,Clock::now());
  write_state(prefix+".final.f64",m,d);std::ofstream out(prefix+".json");
  out<<std::setprecision(17)<<"{\"backend\":\"native\",\"mode\":\"physics\",\"elapsed_s\":"<<elapsed<<",\"steps\":"<<steps<<",\"sim_time\":"<<d->time<<",\"warnings\":"<<warnings(d)<<",\"mujoco_library\":"<<quote(library.dli_fname)<<",\"version\":"<<quote(mj_versionString())<<"}\n";
 }else{
  NativeWindow window(width,height);window.check_size(width,height);
  std::string renderer=reinterpret_cast<const char*>(glGetString(GL_RENDERER)),vendor=reinterpret_cast<const char*>(glGetString(GL_VENDOR)),version=reinterpret_cast<const char*>(glGetString(GL_VERSION));
  std::string lower=renderer;std::transform(lower.begin(),lower.end(),lower.begin(),[](unsigned char c){return std::tolower(c);});
  if(lower.find("llvmpipe")!=std::string::npos||lower.find("softpipe")!=std::string::npos||lower.find("software")!=std::string::npos)throw std::runtime_error("Software rendering is not a valid performance result");
  if(!glXIsDirect(window.display,window.context))throw std::runtime_error("Indirect GLX is not a valid performance result");
  Camera camera(argv[3]);mjvScene scene;mjv_defaultScene(&scene);mjv_makeScene(m,&scene,std::max(10000,4*int(m->ngeom)));
  mjrContext context;mjr_defaultContext(&context);mjr_makeContext(m,&context,mjFONTSCALE_100);
  mjvOption option;mjv_defaultOption(&option);option.flags[mjVIS_CONVEXHULL]=0;
  for(auto&g:option.geomgroup)g=1;
  mjvCamera abstract_camera;mjv_defaultCamera(&abstract_camera);
  std::vector<int> visible(m->ngeom,0);std::ifstream mask(argv[4]);int g;while(mask>>g){if(g<0||g>=m->ngeom)throw std::runtime_error("Invalid visible geom id");visible[g]=1;}
  if(profile=="common"){
   for(int i=0;i<m->nlight;++i)m->light_active[i]=0;
   for(int k=0;k<3;++k){m->vis.headlight.ambient[k]=1;m->vis.headlight.diffuse[k]=0;m->vis.headlight.specular[k]=0;}
   scene.flags[mjRND_SHADOW]=scene.flags[mjRND_REFLECTION]=scene.flags[mjRND_SKYBOX]=scene.flags[mjRND_FOG]=scene.flags[mjRND_HAZE]=0;
  }
  auto update=[&](double t){
   mjv_updateScene(m,d,&option,nullptr,&abstract_camera,mjCAT_ALL,&scene);auto c=camera.at(t);scene.camera[0]=scene.camera[1]=c;
   for(int i=0;i<scene.nlight;++i)if(scene.lights[i].headlight)for(int k=0;k<3;++k){scene.lights[i].pos[k]=c.pos[k];scene.lights[i].dir[k]=c.forward[k];}
   int n=0;for(int i=0;i<scene.ngeom;++i){auto&geom=scene.geoms[i];if(geom.objtype==mjOBJ_GEOM&&(geom.objid<0||!visible[geom.objid]))continue;scene.geoms[n++]=geom;}scene.ngeom=n;
  };
  update(0);mjr_render({0,0,width,height},&scene,&context);glFinish();
  // Capture only before warmup; never read GPU pixels in the measurement loop.
  std::vector<unsigned char>pixels(width*height*3);mjr_readPixels(pixels.data(),nullptr,{0,0,width,height},&context);
  std::ofstream image(prefix+".ppm",std::ios::binary);image<<"P6\n"<<width<<" "<<height<<"\n255\n";for(int y=height-1;y>=0;--y)image.write(reinterpret_cast<char*>(pixels.data()+y*width*3),width*3);image.close();
  std::vector<Frame>rows;rows.reserve(size_t((warmup+sample)*2000));Queries queries;
  auto start=Clock::now(),previous=start;bool measuring=false;int serial=0,sim_steps=0;
  while(true){
   auto frame_start=Clock::now();double elapsed=seconds(start,frame_start);
   if(!measuring&&elapsed>=warmup){restore(m,d,state);start=previous=Clock::now();elapsed=0;sim_steps=0;measuring=true;}
   if(measuring&&elapsed>=sample)break;
   window.poll();Frame row;
   if(mode=="running"){
    auto a=Clock::now();int wanted=int(elapsed/m->opt.timestep);while(sim_steps<wanted){mj_step(m,d);++sim_steps;}row.step_ms=seconds(a,Clock::now())*1000;
   }
   auto a=Clock::now();update(elapsed);row.scene_ms=seconds(a,Clock::now())*1000;
   int slot=serial++%Queries::count;queries.retrieve(slot,rows);bool query=!queries.active[slot];
   if(query)glBeginQuery(GL_TIME_ELAPSED,queries.id[slot]);
   a=Clock::now();mjr_render({0,0,width,height},&scene,&context);row.render_cpu_ms=seconds(a,Clock::now())*1000;
   if(query){glEndQuery(GL_TIME_ELAPSED);queries.active[slot]=true;queries.frame[slot]=measuring?int(rows.size()):-1;}
   a=Clock::now();glXSwapBuffers(window.display,window.window);auto end=Clock::now();row.swap_ms=seconds(a,end)*1000;
   row.frame_ms=seconds(previous,end)*1000;previous=end;row.time=d->time;row.ncon=d->ncon;
   if(measuring)rows.push_back(row);
  }
  double actual_sample=seconds(start,Clock::now());
  glFinish();for(int i=0;i<Queries::count;++i)queries.retrieve(i,rows);
  window.check_size(width,height);
  std::ofstream csv(prefix+".csv");csv<<"frame_ms,step_ms,scene_ms,render_cpu_ms,swap_ms,gpu_ms,sim_time,ncon\n"<<std::setprecision(10);
  for(auto&r:rows)csv<<r.frame_ms<<','<<r.step_ms<<','<<r.scene_ms<<','<<r.render_cpu_ms<<','<<r.swap_ms<<','<<r.gpu_ms<<','<<r.time<<','<<r.ncon<<'\n';
  write_state(prefix+".final.f64",m,d);
  std::ofstream out(prefix+".json");out<<std::setprecision(17)<<"{\"backend\":\"native\",\"mode\":"<<quote(mode.c_str())<<",\"profile\":"<<quote(profile.c_str())<<",\"renderer\":"<<quote(renderer.c_str())<<",\"vendor\":"<<quote(vendor.c_str())<<",\"gl_version\":"<<quote(version.c_str())<<",\"mujoco_version\":"<<quote(mj_versionString())<<",\"mujoco_library\":"<<quote(library.dli_fname)<<",\"frames\":"<<rows.size()<<",\"sim_time\":"<<d->time<<",\"simulated_s\":"<<d->time-state[0]<<",\"sample_s\":"<<sample<<",\"actual_sample_s\":"<<actual_sample<<",\"warnings\":"<<warnings(d)<<",\"width\":"<<width<<",\"height\":"<<height<<",\"vsync_requested\":false,\"ui\":false,\"gpu_timing\":\"GL_TIME_ELAPSED async\"}\n";
  mjr_freeContext(&context);mjv_freeScene(&scene);
 }
 mj_deleteData(d);mj_deleteModel(m);return 0;
}catch(const std::exception&e){std::cerr<<"BENCHMARK ERROR: "<<e.what()<<'\n';return 2;}
