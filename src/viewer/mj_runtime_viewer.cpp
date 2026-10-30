// Copyright 2021 DeepMind Technologies Limited
// Copyright 2026 godot-mujoco contributors
// SPDX-License-Identifier: Apache-2.0
// Adapted from MuJoCo 3.16 simulate; see UPSTREAM.md. No independent physics
// loop.
#include "mj_runtime_viewer.h"
#include "../physics/mj_dictionary_compat.h"
#include "../physics/mj_options.h"
#include "../physics/mj_physics_server.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <iomanip>
#include <limits>
#include <mujoco/mjxmacro.h>
#include <sstream>
#include <type_traits>
namespace godot {
namespace {
constexpr int kMaxGeom = 10000;
constexpr double kSpeeds[] = {
    100, 80, 63,  50,  40, 32, 25,  20, 16, 13,  10,  8,  6.3, 5,   4, 3.2,
    2.5, 2,  1.6, 1.3, 1,  .8, .63, .5, .4, .32, .25, .2, .16, .13, .1};
double timer_ms() {
  return std::chrono::duration<double, std::milli>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}
bool owns_timer = false;
bool main_thread() {
  return OS::get_singleton()->get_thread_caller_id() ==
             OS::get_singleton()->get_main_thread_id() &&
         !bool(ProjectSettings::get_singleton()->get_setting(
             "physics/3d/run_on_separate_thread", false));
}
String object_name(const mjModel *m, int kind, int id) {
  const char *n = mj_id2name(m, kind, id);
  return n ? String::utf8(n) : String::num_int64(id);
}
template <class T> PackedByteArray packed(const T *src, int64_t count) {
  static_assert(std::is_trivially_copyable<T>::value,
                "Only pointer-free SDK value structs");
  PackedByteArray b;
  b.resize(count * sizeof(T));
  if (count)
    std::memcpy(b.ptrw(), src, count * sizeof(T));
  return b;
}
Vector3 vector(const float *p) {
  return mj_to_godot(Vector3(p[0], p[1], p[2]));
}
Basis matrix(const float *p) {
  Basis b;
  for (int r = 0; r < 3; r++)
    for (int c = 0; c < 3; c++)
      b[r][c] = p[3 * r + c];
  return mj_to_godot(b);
}
void sync_bodies(MjPhysicsServer3D &server, MjSpace &s) {
  for (auto &e : server.bodies)
    if (e.second->space == s.rid)
      server.read_body(*e.second);
  s.accumulator = 0;
  s.skip_tick = true;
}
struct VisualField {
  const char *name;
  size_t offset;
  int count;
  bool integer, stat;
};
#define VF(group, name, n)                                                     \
  {#group "." #name, offsetof(mjVisual, group.name), n, false, false}
#define VI(group, name)                                                        \
  {#group "." #name, offsetof(mjVisual, group.name), 1, true, false}
#define SF(name, n) {"stat." #name, offsetof(mjStatistic, name), n, false, true}
const VisualField fields[] = {VI(headlight, active),
                              VF(headlight, ambient, 3),
                              VF(headlight, diffuse, 3),
                              VF(headlight, specular, 3),
                              VI(global, orthographic),
                              VF(global, fovy, 1),
                              SF(center, 3),
                              VF(global, azimuth, 1),
                              VF(global, elevation, 1),
                              SF(extent, 1),
                              VI(global, ellipsoidinertia),
                              VI(global, bvactive),
                              VF(map, stiffness, 1),
                              VF(map, stiffnessrot, 1),
                              VF(map, force, 1),
                              VF(map, torque, 1),
                              VF(map, alpha, 1),
                              VF(map, fogstart, 1),
                              VF(map, fogend, 1),
                              VF(map, znear, 1),
                              VF(map, zfar, 1),
                              VF(map, haze, 1),
                              VF(map, shadowclip, 1),
                              VF(map, shadowscale, 1),
                              SF(meansize, 1),
                              VF(scale, forcewidth, 1),
                              VF(scale, contactwidth, 1),
                              VF(scale, contactheight, 1),
                              VF(scale, connect, 1),
                              VF(scale, com, 1),
                              VF(scale, camera, 1),
                              VF(scale, light, 1),
                              VF(scale, selectpoint, 1),
                              VF(scale, jointlength, 1),
                              VF(scale, jointwidth, 1),
                              VF(scale, actuatorlength, 1),
                              VF(scale, actuatorwidth, 1),
                              VF(scale, framelength, 1),
                              VF(scale, framewidth, 1),
                              VF(scale, constraint, 1),
                              VF(scale, slidercrank, 1),
                              VF(rgba, fog, 4),
                              VF(rgba, haze, 4),
                              VF(rgba, force, 4),
                              VF(rgba, inertia, 4),
                              VF(rgba, joint, 4),
                              VF(rgba, actuator, 4),
                              VF(rgba, actuatornegative, 4),
                              VF(rgba, actuatorpositive, 4),
                              VF(rgba, com, 4),
                              VF(rgba, camera, 4),
                              VF(rgba, light, 4),
                              VF(rgba, selectpoint, 4),
                              VF(rgba, connect, 4),
                              VF(rgba, contactpoint, 4),
                              VF(rgba, contactforce, 4),
                              VF(rgba, contactfriction, 4),
                              VF(rgba, contacttorque, 4),
                              VF(rgba, contactgap, 4),
                              VF(rgba, rangefinder, 4),
                              VF(rgba, constraint, 4),
                              VF(rgba, slidercrank, 4),
                              VF(rgba, crankbroken, 4),
                              VF(rgba, frustum, 4),
                              VF(rgba, bv, 4),
                              VF(rgba, bvactive, 4)};
#undef VF
#undef VI
#undef SF
bool visual_supported(MjViewerState &v, const String &name) {
  return v.native_backend ||
         (!name.begins_with("headlight.") && !name.begins_with("map.fog") &&
          !name.begins_with("map.shadow") && name != "map.haze" &&
          name != "map.alpha" && name != "rgba.fog" && name != "rgba.haze");
}
Array visual_fields(MjViewerState &v) {
  Array result;
  for (auto &f : fields) {
    Dictionary d;
    d["name"] = f.name;
    d["integer"] = f.integer;
    d["supported"] = visual_supported(v, f.name);
    d["reason"] = visual_supported(v, f.name)
                      ? String()
                      : String("Godot keeps its authored lighting/environment; "
                               "this OpenGL setting is unavailable");
    Array values;
    const char *p = f.stat ? reinterpret_cast<const char *>(&v.model->stat)
                           : reinterpret_cast<const char *>(&v.model->vis);
    p += f.offset;
    for (int i = 0; i < f.count; i++)
      values.append(f.integer ? double(reinterpret_cast<const int *>(p)[i])
                    : f.stat  ? reinterpret_cast<const mjtNum *>(p)[i]
                              : reinterpret_cast<const float *>(p)[i]);
    d["values"] = values;
    result.append(d);
  }
  return result;
}
String set_visual(MjViewerState &v, const Dictionary &cmd) {
  String name = cmd.get("name", String());
  Array values = cmd.get("values", Array());
  for (auto &f : fields)
    if (name == f.name) {
      if (!visual_supported(v, name))
        return "MuJoCo OpenGL visual field unavailable in Godot renderer";
      if (values.size() != f.count)
        return "Wrong visual field width";
      for (int i = 0; i < f.count; i++)
        if (!std::isfinite(double(values[i])) ||
            std::abs(double(values[i])) > std::numeric_limits<float>::max())
          return "Nonfinite visual parameter";
      double x = values[0];
      if ((name == "global.fovy" &&
           (x <= 0 || (!v.model->vis.global.orthographic && x >= 180))) ||
          (name == "stat.extent" && x <= 0) ||
          (name == "stat.meansize" && x <= 0) ||
          (name == "map.znear" && (x <= 0 || x >= v.model->vis.map.zfar)) ||
          (name == "map.zfar" && x <= v.model->vis.map.znear))
        return "Invalid visual range";
      char *p = f.stat ? reinterpret_cast<char *>(&v.model->stat)
                       : reinterpret_cast<char *>(&v.model->vis);
      p += f.offset;
      for (int i = 0; i < f.count; i++) {
        if (f.integer)
          reinterpret_cast<int *>(p)[i] = int(values[i]) != 0;
        else if (f.stat)
          reinterpret_cast<mjtNum *>(p)[i] = double(values[i]);
        else
          reinterpret_cast<float *>(p)[i] = double(values[i]);
      }
      return {};
    }
  return "Unknown visual parameter";
}
bool flag_supported(int i, const mjModel *m) {
  return !((i >= mjVIS_FLEXVERT && i <= mjVIS_FLEXSKIN && !m->nflex) ||
           (i == mjVIS_SKIN && !m->nskin));
}
Dictionary catalog(MjSpace &s, const String &backend) {
  auto &v = *s.viewer;
  auto *m = v.model;
  Dictionary c;
  Array vis, rnd, groups, cameras, geoms, bodies, keys, image_sensors;
  for (int i = 0; i < mjNVISFLAG; i++) {
    Dictionary x;
    x["id"] = i;
    x["name"] = mjVISSTRING[i][0];
    x["shortcut"] = mjVISSTRING[i][2];
    x["value"] = bool(v.option.flags[i]);
    bool ok =
        flag_supported(i, m) &&
        (backend == "native" || (i != mjVIS_CONVEXHULL && i != mjVIS_TEXTURE &&
                                 i != mjVIS_ACTIVATION && i != mjVIS_ISLAND &&
                                 i != mjVIS_TRANSPARENT && i != mjVIS_PERTOBJ));
    x["supported"] = ok;
    x["reason"] = ok ? String()
                     : String(flag_supported(i, m)
                                  ? "Godot keeps authored surface materials; "
                                    "this MuJoCo surface effect is unavailable"
                                  : "Current rigid model has no flex/skin");
    vis.append(x);
  }
  for (int i = 0; i < mjNRNDFLAG; i++) {
    Dictionary x;
    x["id"] = i;
    x["name"] = mjRNDSTRING[i][0];
    x["shortcut"] = mjRNDSTRING[i][2];
    x["value"] = bool(v.render_flags[i]);
    bool ok = backend == "native";
    x["supported"] = ok;
    x["reason"] = ok ? String()
                     : String("MuJoCo OpenGL effect; Godot uses its scene "
                              "materials/environment");
    rnd.append(x);
  }
  for (const char *name :
       {"geom", "site", "joint", "tendon", "actuator", "flex", "skin"}) {
    Dictionary x;
    x["name"] = name;
    x["supported"] = String(name) != "flex" && String(name) != "skin";
    groups.append(x);
  }
  cameras.append("Free");
  cameras.append("Tracking");
  for (int i = 0; i < m->ncam; i++)
    cameras.append(object_name(m, mjOBJ_CAMERA, i));
  for (int i = 1; i < m->nbody; i++) {
    Dictionary body;
    body["id"] = i;
    body["name"] = object_name(m, mjOBJ_BODY, i);
    bodies.append(body);
  }
  for (int i = 0; i < m->nkey; i++) {
    Dictionary key;
    key["id"] = i;
    key["name"] = object_name(m, mjOBJ_KEY, i);
    keys.append(key);
  }
  for (int i = 0; i < m->nsensor; i++) {
    int width = m->sensor_intprm[mjNSENS * i];
    int height = m->sensor_intprm[mjNSENS * i + 1];
    if (m->sensor_type[i] == mjSENS_USER && width > 0 && height > 0 &&
        m->sensor_dim[i] > 0 && m->sensor_dim[i] % 3 == 0 &&
        int64_t(width) * height == m->sensor_dim[i] / 3) {
      Dictionary image;
      image["id"] = i;
      image["name"] = object_name(m, mjOBJ_SENSOR, i);
      image_sensors.append(image);
    }
  }
  for (int i = 0; i < m->ngeom; i++) {
    Dictionary g;
    g["id"] = i;
    g["name"] = object_name(m, mjOBJ_GEOM, i);
    g["group"] = int(m->geom_group[i]);
    if (i < int(s.geom_owners.size())) {
      auto id = s.geom_owners[i].first;
      g["owner_rid"] = id;
      auto owner = s.committed_bodies.find(id.get_id());
      if (owner != s.committed_bodies.end())
        g["object_id"] = int64_t(owner->second.object_id);
    }
    auto imported = s.imported_query_owners.find(i);
    if (imported != s.imported_query_owners.end() &&
        imported->second->object_id)
      g["object_id"] = int64_t(imported->second->object_id);
    geoms.append(g);
  }
  c["backend"] = backend;
  c["vis"] = vis;
  c["rnd"] = rnd;
  c["groups"] = groups;
  c["cameras"] = cameras;
  c["bodies"] = bodies;
  c["geoms"] = geoms;
  c["keyframes"] = keys;
  c["nkey"] = int(m->nkey);
  c["keyframe_reason"] = m->nkey ? String() : String("No model keyframes. The existing shared-world composition does not accept source models with keyframes; original design data is retained by the editor.");
  c["image_sensors"] = image_sensors;
  c["save_xml_supported"] = !s.compiled_xml.is_empty();
  Array disable_names, enable_names;
  for (int i = 0; i < mjNDISABLE; i++)
    disable_names.append(mjDISABLESTRING[i]);
  for (int i = 0; i < mjNENABLE; i++)
    enable_names.append(mjENABLESTRING[i]);
  c["physics_disable_names"] = disable_names;
  c["physics_enable_names"] = enable_names;
  c["visual"] = visual_fields(v);
  c["labels"] =
      String("None,Body,Joint,Geom,Site,Camera,Light,Tendon,Actuator,"
             "Constraint,Flex,Skin,Selection,Sel Pnt,Contact,Force,Island")
          .split(",");
  c["frames"] =
      String("None,Body,Geom,Site,Camera,Light,Contact,World").split(",");
  return c;
}
MjViewerState *ensure(MjSpace &s) {
  if (!s.model || !s.data || s.dirty || s.design_blocked)
    return nullptr;
  if (s.viewer && s.viewer->revision == s.revision)
    return s.viewer.get();
  gmj_viewer_invalidate(s);
  int state_size = mj_stateSize(s.model, mjSTATE_INTEGRATION);
  if (state_size <= 0 || state_size > 1048576 || s.model->nflex ||
      s.model->nskin)
    return nullptr;
  int capacity = std::min(2000, int(100000000 / (sizeof(mjtNum) * state_size)));
  long double budget =
      sizeof(mjModel) +
      3 * (static_cast<long double>(s.data->nbuffer) + s.data->narena +
           kMaxGeom * (sizeof(mjvGeom) + sizeof(int))) +
      static_cast<long double>(capacity + 1) * state_size * sizeof(mjtNum);
  if (budget > 256.L * 1024 * 1024)
    return nullptr;
  auto v = std::make_shared<MjViewerState>();
  // mjv_* takes const model arrays. On the main thread we can share those
  // immutable revision-owned arrays while keeping display-only vis/stat local.
  // This avoids duplicating large meshes/textures just to pick or move a
  // camera.
  v->model = new mjModel(*s.model);
  if (!v->model)
    return nullptr;
  v->revision = s.revision;
  mjv_defaultCamera(&v->camera);
  mjv_defaultFreeCamera(v->model, &v->camera);
  mjv_defaultOption(&v->option);
  mjv_defaultPerturb(&v->perturb);
  for (int i = 0; i < mjNRNDFLAG; i++)
    v->render_flags[i] = mjRNDSTRING[i][1][0] == '1';
  v->state_size = mj_stateSize(s.model, mjSTATE_INTEGRATION);
  if (v->state_size > 0 && v->state_size <= 1048576) {
    v->history_capacity =
        std::min(2000, int(100000000 / (sizeof(mjtNum) * v->state_size)));
    v->history.resize(size_t(v->history_capacity) * v->state_size);
  }
  s.viewer = v;
  v->add_history(s);
  return v.get();
}
MjViewerFrame *find_frame(MjViewerState &v, int64_t id) {
  for (auto &f : v.frames)
    if (f->id == id)
      return f.get();
  return nullptr;
}
mjtByte *group(MjViewerState &v, const String &name) {
  if (name == "geom")
    return v.option.geomgroup;
  if (name == "site")
    return v.option.sitegroup;
  if (name == "joint")
    return v.option.jointgroup;
  if (name == "tendon")
    return v.option.tendongroup;
  if (name == "actuator")
    return v.option.actuatorgroup;
  if (name == "flex")
    return v.option.flexgroup;
  if (name == "skin")
    return v.option.skingroup;
  return nullptr;
}
Dictionary settings(MjViewerState &v) {
  Dictionary d;
  Array flags, rnd;
  for (int i = 0; i < mjNVISFLAG; i++)
    flags.append(bool(v.option.flags[i]));
  for (int i = 0; i < mjNRNDFLAG; i++)
    rnd.append(bool(v.render_flags[i]));
  d["vis"] = flags;
  d["rnd"] = rnd;
  d["frame"] = v.option.frame;
  d["label"] = v.option.label;
  d["bvh_depth"] = v.option.bvh_depth;
  d["flex_layer"] = v.option.flex_layer;
  Dictionary g;
  for (const char *n :
       {"geom", "site", "joint", "tendon", "actuator", "flex", "skin"}) {
    Array a;
    auto *p = group(v, n);
    for (int i = 0; i < mjNGROUP; i++)
      a.append(bool(p[i]));
    g[n] = a;
  }
  d["groups"] = g;
  d["visual"] = visual_fields(v);
  return d;
}
String copy_key(MjSpace &s, bool precise) {
  auto *m = s.model;
  auto *d = s.data;
  std::ostringstream o;
  o.imbue(std::locale::classic());
  o << std::setprecision(precise ? 16 : 6) << "<key time=\"" << d->time << "\"";
  auto attr = [&](const char *n, const mjtNum *p, int count) {
    if (!count)
      return;
    o << " " << n << "=\"";
    for (int i = 0; i < count; i++) {
      if (i)
        o << " ";
      o << p[i];
    }
    o << "\"";
  };
  attr("qpos", d->qpos, m->nq);
  attr("qvel", d->qvel, m->nv);
  attr("act", d->act, m->na);
  attr("ctrl", d->ctrl, m->nu);
  attr("mpos", d->mocap_pos, 3 * m->nmocap);
  attr("mquat", d->mocap_quat, 4 * m->nmocap);
  o << "/>";
  return String::utf8(o.str().c_str());
}
// The canonical XML belongs to this committed world, unlike mj_saveLastXML's
// process-global parser slot. Keyframe edits are session model values, so overlay
// that block without reparsing/recompiling (and duplicating) a potentially large
// world just to export it. The rest is already canonical compiled MJCF.
String export_xml(MjSpace &s) {
  String xml = s.compiled_xml;
  int begin = xml.find("<keyframe");
  if (begin >= 0) {
    int end = xml.find("</keyframe>", begin);
    if (end < 0)
      return {};
    xml = xml.substr(0, begin) + xml.substr(end + 11);
  }
  int close = xml.rfind("</mujoco>");
  if (close < 0)
    return {};
  auto *m = s.model;
  std::ostringstream out;
  out.imbue(std::locale::classic());
  out << std::setprecision(17);
  if (m->nkey) {
    out << "  <keyframe>\n";
    for (int k = 0; k < m->nkey; k++) {
      out << "    <key name=\"" << object_name(m, mjOBJ_KEY, k).xml_escape(true).utf8().get_data()
          << "\" time=\"" << m->key_time[k] << '"';
      auto values = [&](const char *name, const mjtNum *p, int count) {
        if (!count)
          return;
        out << ' ' << name << "=\"";
        for (int i = 0; i < count; i++)
          out << (i ? " " : "") << p[i];
        out << '"';
      };
      values("qpos", m->key_qpos + k * m->nq, m->nq);
      values("qvel", m->key_qvel + k * m->nv, m->nv);
      values("act", m->key_act + k * m->na, m->na);
      values("ctrl", m->key_ctrl + k * m->nu, m->nu);
      values("mpos", m->key_mpos + k * 3 * m->nmocap, 3 * m->nmocap);
      values("mquat", m->key_mquat + k * 4 * m->nmocap, 4 * m->nmocap);
      out << "/>\n";
    }
    out << "  </keyframe>\n";
  }
  return xml.substr(0, close) + String::utf8(out.str().c_str()) + xml.substr(close);
}
template <class T> double numeric(const T *p, int i) {
  if constexpr (std::is_same<T, mjtNum>::value)
    return p[i];
  else
    return 0.;
}
Dictionary inspect(MjSpace &s, const Dictionary &opts) {
  auto *m = s.model;
  auto *d = s.data;
  auto &v = *s.viewer;
  Dictionary out;
  Array joints, controls, equalities, sensors;
  for (int j = 0; j < m->njnt; j++) {
    if (m->jnt_type[j] != mjJNT_HINGE && m->jnt_type[j] != mjJNT_SLIDE)
      continue;
    if (!v.option.jointgroup[std::clamp(m->jnt_group[j], 0, mjNGROUP - 1)])
      continue;
    Dictionary x;
    x["id"] = j;
    x["name"] = object_name(m, mjOBJ_JOINT, j);
    x["value"] = d->qpos[m->jnt_qposadr[j]];
    x["limited"] = bool(m->jnt_limited[j]);
    x["min"] = m->jnt_limited[j]               ? m->jnt_range[2 * j]
               : m->jnt_type[j] == mjJNT_HINGE ? -Math_PI
                                               : -1.;
    x["max"] = m->jnt_limited[j]               ? m->jnt_range[2 * j + 1]
               : m->jnt_type[j] == mjJNT_HINGE ? Math_PI
                                               : 1.;
    x["disabled"] = !s.paused;
    joints.append(x);
  }
  for (int i = 0; i < m->nu; i++) {
    int a = m->actuator_trnid[2 * i];
    (void)a;
    if (!v.option
             .actuatorgroup[std::clamp(m->actuator_group[i], 0, mjNGROUP - 1)])
      continue;
    Dictionary x;
    x["id"] = i;
    x["name"] = object_name(m, mjOBJ_ACTUATOR, i);
    x["value"] = d->ctrl[i];
    x["limited"] = bool(m->actuator_ctrllimited[i]);
    x["min"] = m->actuator_ctrllimited[i] ? m->actuator_ctrlrange[2 * i] : -1.;
    x["max"] =
        m->actuator_ctrllimited[i] ? m->actuator_ctrlrange[2 * i + 1] : 1.;
    x["disabled"] = m->actuator_group[i] >= 0 && m->actuator_group[i] <= 30 &&
                    bool(m->opt.disableactuator & (1 << m->actuator_group[i]));
    controls.append(x);
  }
  for (int i = 0; i < m->neq; i++) {
    Dictionary x;
    x["id"] = i;
    x["name"] = object_name(m, mjOBJ_EQUALITY, i);
    x["value"] = bool(d->eq_active[i]);
    equalities.append(x);
  }
  if (bool(opts.get("sensors", false)))
    for (int i = 0; i < m->nsensor; i++) {
      Dictionary x;
      x["id"] = i;
      x["name"] = object_name(m, mjOBJ_SENSOR, i);
      int dim = m->sensor_dim[i], adr = m->sensor_adr[i];
      PackedFloat64Array values;
      int width = m->sensor_intprm[mjNSENS * i],
          height = m->sensor_intprm[mjNSENS * i + 1];
      bool image = m->sensor_type[i] == mjSENS_USER && width > 0 &&
                   height > 0 && dim > 0 && dim % 3 == 0 &&
                   int64_t(width) * height == dim / 3 &&
                   dim <= 12 * 1024 * 1024;
      x["image"] = image;
      if (image) {
        double version = d->sensordata[adr + dim - 1];
        x["version"] = version;
        x["width"] = width;
        x["height"] = height;
        if (version != 0 && std::isfinite(version)) {
          PackedByteArray rgb;
          rgb.resize(dim);
          bool finite = true;
          for (int j = 0; j < dim - 1; j++) {
            double q = d->sensordata[adr + j];
            if (!std::isfinite(q)) {
              finite = false;
              break;
            }
            rgb.set(j, uint8_t(std::clamp(q, 0., 255.)));
          }
          rgb.set(dim - 1, 0);
          if (finite)
            x["rgb"] = rgb;
          else
            x["error"] = "Nonfinite image data";
        }
      } else {
        for (int j = 0; j < std::min(dim, 1000); j++)
          values.append(d->sensordata[adr + j] /
                        (m->sensor_cutoff[i] > 0 ? m->sensor_cutoff[i] : 1));
        x["values"] = values;
        x["cutoff"] = m->sensor_cutoff[i];
      }
      sensors.append(x);
    }
  out["joints"] = joints;
  out["controls"] = controls;
  out["equalities"] = equalities;
  out["sensors"] = sensors;
  out["physics_read_only"] = true;
  out["physics"] = gmj_options(m->opt);
  String field = opts.get("watch_field", String("qpos"));
  int index = opts.get("watch_index", 0);
  out["watch_field"] = field;
  out["watch_index"] = index;
  String watch_error = "Invalid numeric field";
#define X(TYPE, NAME, NR, NC)                                                  \
  if (field == #NAME && std::is_same<TYPE, mjtNum>::value) {                   \
    int64_t count = int64_t(m->NR) * (NC);                                     \
    if (index >= 0 && index < count) {                                         \
      out["watch_value"] = numeric(d->NAME, index);                            \
      watch_error = "";                                                        \
    } else                                                                     \
      watch_error = "Invalid index";                                           \
  }
  MJDATA_POINTERS
#undef X
  out["watch_error"] = watch_error;
  auto cfg = mju_getLogConfig();
  Dictionary log;
  log["console"] = bool(cfg.logto_console);
  log["file"] = bool(cfg.logto_file);
  log["path"] = String::utf8(cfg.logfile);
  log["topics"] = cfg.topics;
  Array topics;
  for (int i = 0; i < mjNTOPIC; i++)
    topics.append(mjTOPICSTRING[i]);
  log["topic_names"] = topics;
  out["logging"] = log;
  out["profiler"] = v.profiler;
  return out;
}
} // namespace
MjViewerFrame::MjViewerFrame(const mjModel *m) {
  data = mj_makeData(m);
  mjv_defaultScene(&scene);
  mjv_makeScene(m, &scene, kMaxGeom);
}
MjViewerFrame::~MjViewerFrame() {
  mjv_freeScene(&scene);
  if (data)
    mj_deleteData(data);
}
MjViewerState::~MjViewerState() {
  frames.clear();
  spare_frames.clear();
  delete model;
}
void MjViewerState::cancel(MjSpace &s) {
  if (s.data && wrench_body > 0 && wrench_body < s.model->nbody &&
      applied_wrench.size() == 6)
    for (int i = 0; i < 6; i++)
      s.data->xfrc_applied[6 * wrench_body + i] -= applied_wrench[i];
  applied_wrench.clear();
  last_wrench.clear();
  last_wrench_body = 0;
  wrench_body = 0;
  perturb.active = 0;
}
void MjViewerState::add_history(MjSpace &s) {
  if (!history_capacity)
    return;
  history_cursor = (history_cursor + 1) % history_capacity;
  mj_getState(s.model, s.data,
              history.data() + size_t(history_cursor) * state_size,
              mjSTATE_INTEGRATION);
  history_count = std::min(history_count + 1, history_capacity);
  scrub = 0;
}
void gmj_viewer_install_timer() {
  if (!mjcb_time) {
    mjcb_time = timer_ms;
    owns_timer = true;
  }
}
void gmj_viewer_remove_timer() {
  if (owns_timer && mjcb_time == timer_ms)
    mjcb_time = nullptr;
  owns_timer = false;
}
void gmj_viewer_invalidate(MjSpace &s) {
  if (s.viewer && s.viewer->revision == s.revision)
    s.viewer->cancel(s);
  s.viewer.reset();
  s.viewer_speed = 1;
}
void gmj_viewer_capture_snapshot(MjSpace &s) {
  auto *v = ensure(s);
  if (!v)
    return;
  v->cancel(s);
  v->snapshot.resize(v->state_size);
  mj_getState(s.model, s.data, v->snapshot.data(), mjSTATE_INTEGRATION);
}
String gmj_viewer_restore_snapshot(MjSpace &s) {
  auto *v = ensure(s);
  if (!v || v->snapshot.size() != size_t(v->state_size))
    return "No snapshot for this model revision";
  v->cancel(s);
  mj_setState(s.model, s.data, v->snapshot.data(), mjSTATE_INTEGRATION);
  mj_forward(s.model, s.data);
  s.accumulator = 0;
  return {};
}
void gmj_viewer_begin_batch(MjSpace &s) {
  if (s.viewer && s.viewer->revision == s.revision)
    std::memcpy(s.viewer->timers, s.data->timer, sizeof(s.viewer->timers));
}
void gmj_viewer_before_step(MjSpace &s) {
  if (!s.viewer || s.viewer->revision != s.revision)
    return;
  auto &v = *s.viewer;
  // Reset/rollback can replace mjData without changing the model revision.
  if (v.num_threads && !s.data->threadpool)
    mju_threadpool(s.data, v.num_threads);
  // simulate::InjectNoise, MuJoCo 3.16: Ornstein-Uhlenbeck control noise.
  if (v.noise_std > 0) {
    auto *m = s.model;
    double rate = v.noise_rate > 0 ? std::exp(-m->opt.timestep / v.noise_rate) : 0;
    double scale = v.noise_std * std::sqrt(1 - rate * rate);
    for (int i = 0; i < m->nu; i++) {
      bool limited = m->actuator_ctrllimited[i];
      double bottom = limited ? m->actuator_ctrlrange[2 * i] : 0;
      double top = limited ? m->actuator_ctrlrange[2 * i + 1] : 0;
      double midpoint = m->nkey ? m->key_ctrl[v.key * m->nu + i] : (bottom + top) / 2;
      double halfrange = limited ? (top - bottom) / 2 : 1;
      s.data->ctrl[i] = rate * s.data->ctrl[i] + (1 - rate) * midpoint +
                        scale * halfrange * mju_standardNormal(nullptr);
      if (limited)
        s.data->ctrl[i] = std::clamp(s.data->ctrl[i], bottom, top);
    }
  }
  // Previous viewer wrench was removed after the preceding substep. Apply into
  // a scratch six-vector, then add it to the caller-owned external wrench.
  if (!v.perturb.active || v.perturb.select <= 0)
    return;
  int b = v.perturb.select;
  mjtNum old[6];
  mju_copy(old, s.data->xfrc_applied + 6 * b, 6);
  mju_zero(s.data->xfrc_applied + 6 * b, 6);
  mjv_applyPerturbPose(v.model, s.data, &v.perturb, 0);
  mjv_applyPerturbForce(v.model, s.data, &v.perturb);
  v.applied_wrench.resize(6);
  v.wrench_body = b;
  for (int i = 0; i < 6; i++) {
    v.applied_wrench[i] = s.data->xfrc_applied[6 * b + i];
    s.data->xfrc_applied[6 * b + i] += old[i];
  }
}
void gmj_viewer_update_paused(MjSpace &s) {
  if (!s.viewer || s.viewer->revision != s.revision || s.dirty || s.design_blocked ||
      !s.model || !s.data)
    return;
  // simulate/main.cc paused branch: update the authoritative diagnostics and,
  // optionally, converge the warm start. No time/integration/history advance.
  if (s.viewer->num_threads && !s.data->threadpool)
    mju_threadpool(s.data, s.viewer->num_threads);
  double before = s.data->timer[mjTIMER_FORWARD].duration;
  mj_forward(s.model, s.data);
  s.viewer->paused_cpu_ms = mjcb_time == timer_ms ? s.data->timer[mjTIMER_FORWARD].duration - before : 0;
  if (s.viewer->pause_update)
    mju_copy(s.data->qacc_warmstart, s.data->qacc, s.model->nv);
}
void gmj_viewer_after_step(MjSpace &s) {
  if (!s.viewer || s.viewer->revision != s.revision)
    return;
  auto &v = *s.viewer;
  if (v.wrench_body > 0 && v.applied_wrench.size() == 6) {
    v.last_wrench = v.applied_wrench;
    v.last_wrench_body = v.wrench_body;
    for (int i = 0; i < 6; i++)
      s.data->xfrc_applied[6 * v.wrench_body + i] -= v.applied_wrench[i];
    v.applied_wrench.clear();
    v.wrench_body = 0;
  }
}
void gmj_viewer_after_batch(MjSpace &s) {
  if (!s.viewer || s.viewer->revision != s.revision)
    return;
  auto &v = *s.viewer;
  v.add_history(s);
  auto *d = s.data;
  auto *m = s.model;
  Dictionary p;
  Array counts, costs;
  int iterations = 0;
  int islands = d->nefc ? std::max(1, std::min(d->nisland, mjNISLAND)) : 0;
  for (int k = 0; k < islands; k++) {
    int n = std::min(d->solver_niter[k], mjNSOLVER);
    iterations += d->solver_niter[k];
    for (int line = 0; v.profiler_enabled && line < 5; line++) {
      if ((m->opt.solver == mjSOL_PGS && line >= 3) ||
          (m->opt.solver == mjSOL_CG && line == 4))
        continue;
      PackedFloat64Array a;
      for (int i = 0; i < n; i++) {
        auto &t = d->solver[k * mjNSOLVER + i];
        a.append(line == 0   ? (islands == 1 ? d->nefc : d->island_nefc[k])
                 : line == 1 ? t.nactive
                 : line == 2 ? t.nchange
                 : line == 3 ? t.neval
                             : t.nupdate);
      }
      counts.append(a);
    }
    for (int line = 0; v.profiler_enabled && line < 3; line++) {
      if (m->opt.solver == mjSOL_PGS && line > 0)
        continue;
      PackedFloat64Array a;
      for (int i = 0; i < n; i++) {
        auto &t = d->solver[k * mjNSOLVER + i];
        a.append(std::log10(std::max(mjMINVAL, line == 0   ? t.improvement
                                               : line == 1 ? t.gradient
                                                           : t.lineslope)));
      }
      costs.append(a);
    }
  }
  double error = 0;
  for (int k = 0; k < islands; k++) {
    int n = std::min(d->solver_niter[k], mjNSOLVER);
    if (n) {
      auto &t = d->solver[k * mjNSOLVER + n - 1];
      double q = std::min(t.improvement, t.gradient);
      if (q == 0)
        q = std::max(t.improvement, t.gradient);
      error = std::max(error, q);
    }
  }
  p["solver_log_error"] = std::log10(std::max(mjMINVAL, error));
  p["counts"] = counts;
  p["costs"] = costs;
  p["iterations"] = iterations;
  p["islands"] = islands;
  p["time"] = d->time;
  p["timing_available"] = mjcb_time == timer_ms;
  auto delta = [&](int t) {
    return d->timer[t].duration - v.timers[t].duration;
  };
  int number = d->timer[mjTIMER_STEP].number - v.timers[mjTIMER_STEP].number;
  double div = std::max(1, number), total = delta(mjTIMER_STEP) / div;
  Array timing;
  timing.append(total);
  timing.append(delta(mjTIMER_POS_COLLISION) / div);
  timing.append((delta(mjTIMER_POS_MAKE) + delta(mjTIMER_POS_PROJECT)) / div);
  timing.append(delta(mjTIMER_CONSTRAINT) / div);
  timing.append(total - double(timing[1]) - double(timing[2]) -
                double(timing[3]));
  p["timing_ms"] = timing;
  Array sizes;
  sizes.append(int(m->nv));
  sizes.append(int(m->nbody));
  sizes.append(d->nefc);
  mjtNum nnz = 0;
  for (int k = 0; k < islands; k++)
    nnz += d->solver_nnz[k];
  sizes.append(std::sqrt(nnz));
  sizes.append(d->ncon);
  sizes.append(double(iterations) / std::max(1, islands));
  p["sizes"] = sizes;
  replace_dictionary(v.profiler, p);
  std::memcpy(v.timers, d->timer, sizeof(v.timers));
}
int64_t MjPhysicsServer3D::scene_viewer_request(const RID &rid,
                                                int64_t revision, int64_t frame,
                                                int64_t sequence,
                                                const Dictionary &command) {
  if (!main_thread() || Engine::get_singleton()->is_editor_hint())
    return 0;
  std::lock_guard<std::mutex> lock(requests_mutex);
  auto *s = space(rid);
  const bool saturated =
      viewer_commands.size() >= 128 || world_command_results.size() >= 256;
  if (saturated && String(command.get("action", String())) == "cancel" && s &&
      s->viewer) {
    auto &v = *s->viewer;
    v.cancel_pending = true;
    v.cancel_sequence = std::max(v.cancel_sequence, sequence);
    v.release_pending |= bool(command.get("release_frames", false));
  }
  if (saturated)
    return 0;
  if (s && s->viewer && int64_t(s->revision) == revision) {
    if (auto *f = find_frame(*s->viewer, frame))
      f->pins++;
  }
  int64_t id = next_request_id++;
  viewer_commands.push_back(
      {id, revision, frame, sequence, rid, command.duplicate(true)});
  return id;
}
void MjPhysicsServer3D::process_viewer_commands() {
  // End/cancel must release forces even if the normal request queues were full.
  // Earlier queued motions cannot restart a gesture after this boundary.
  for (auto &entry : spaces) {
    auto &s = *entry.second;
    if (!s.viewer || s.viewer->revision != s.revision ||
        !s.viewer->cancel_pending)
      continue;
    auto &v = *s.viewer;
    v.cancel(s);
    if (v.release_pending) {
      v.frames.clear();
      v.presented = 0;
    }
    v.cancel_pending = v.release_pending = false;
  }
  std::deque<ViewerCommand> pending;
  {
    std::lock_guard<std::mutex> lock(requests_mutex);
    pending.swap(viewer_commands);
  }
  for (auto &r : pending) {
    Dictionary result;
    result["request"] = r.request;
    String action = r.command.get("action", String());
    result["command"] = action;
    bool deferred = false;
    auto apply = [&]() -> String {
      auto *s = space(r.space);
      if (!s)
        return "Viewer world was removed";
      if (action == "cancel") {
        if (s->viewer) {
          s->viewer->cancel(*s);
          if (bool(r.command.get("release_frames", false))) {
            s->viewer->frames.clear();
            s->viewer->presented = 0;
          }
        }
        return {};
      }
      if (s->dirty || s->design_blocked)
        return "Wait for committed model";
      if (int64_t(s->revision) != r.revision) {
        if (s->viewer && s->viewer->revision == s->revision)
          s->viewer->cancel(*s);
        return "Stale model revision";
      }
      auto *v = ensure(*s);
      if (!v)
        return "No committed viewer model";
      if (r.sequence <= v->sequence)
        return "Stale input sequence";
      v->sequence = r.sequence;
      auto *m = s->model;
      auto *d = s->data;
      auto &cmd = r.command;
      if ((action == "perturb_begin" ||
           (action == "move" && bool(cmd.get("perturb", true)))) &&
          r.sequence <= v->cancel_sequence)
        return {};
      auto *f = find_frame(*v, r.frame);
      if ((action == "select" || action == "perturb_begin" ||
           action == "move") &&
          !f) {
        v->cancel(*s);
        return "Displayed frame expired";
      }
      if (action == "seed_camera") {
        if (v->seeded)
          return {};
        Transform3D t = cmd.get("transform", Transform3D());
        if (!t.is_finite())
          return "Invalid authored camera";
        Vector3 p = godot_to_mj(t.origin),
                forward = godot_to_mj(-t.basis.get_column(2)).normalized();
        double distance = cmd.get("distance", v->camera.distance);
        if (!std::isfinite(distance) || distance <= 0)
          distance = std::max(1., v->model->stat.extent);
        bool orthographic = cmd.get("orthographic", false);
        double fovy = cmd.get("fovy", 45.);
        double near = cmd.get("near", .05), far = cmd.get("far", 4000.);
        Vector2 offset = cmd.get("offset", Vector2());
        if (!std::isfinite(fovy) || fovy <= 0 || (!orthographic && fovy >= 180) ||
            !std::isfinite(near) || !std::isfinite(far) || near <= 0 || far <= near ||
            far > std::numeric_limits<float>::max() || !offset.is_finite())
          return "Invalid authored clipping planes or projection";
        double height = cmd.get("frustum_size", orthographic ? fovy :
            2 * near * std::tan(fovy * Math_PI / 360));
        if (!std::isfinite(height) || height <= 0 || height > std::numeric_limits<float>::max())
          return "Invalid authored projection";
        for (int k = 0; k < 3; k++)
          v->camera.lookat[k] = p[k] + forward[k] * distance;
        v->camera.distance = distance;
        v->camera.azimuth = std::atan2(forward.y, forward.x) * 180 / Math_PI;
        v->camera.elevation =
            std::atan2(forward.z, std::hypot(forward.x, forward.y)) * 180 /
            Math_PI;
        v->camera.orthographic = orthographic;
        v->model->vis.global.fovy = fovy;
        auto &c = v->authored_camera;
        Vector3 up = godot_to_mj(t.basis.get_column(1)).normalized();
        for (int k = 0; k < 3; k++) {
          c.pos[k] = p[k];
          c.forward[k] = forward[k];
          c.up[k] = up[k];
        }
        c.orthographic = v->camera.orthographic;
        c.frustum_near = near;
        c.frustum_far = far;
        c.frustum_bottom = -height / 2 + offset.y;
        c.frustum_top = height / 2 + offset.y;
        c.frustum_center = offset.x;
        v->model->vis.map.znear = c.frustum_near / v->model->stat.extent;
        v->model->vis.map.zfar = c.frustum_far / v->model->stat.extent;
        v->authored_camera_active = true;
        v->seeded = true;
        return {};
      }
      if (action == "move") {
        int mouse = cmd.get("mouse", int(mjMOUSE_ROTATE_V));
        double dx = cmd.get("dx", 0.), dy = cmd.get("dy", 0.);
        if (mouse < mjMOUSE_ROTATE_V || mouse > mjMOUSE_ZOOM ||
            !std::isfinite(dx) || !std::isfinite(dy))
          return "Invalid mouse movement";
        if (bool(cmd.get("perturb", bool(v->perturb.active)))) {
          if (!v->perturb.active)
            return {}; // The gesture ended while this motion was queued.
          mjv_movePerturb(v->model, d, mouse, dx, dy, &f->scene, &v->perturb);
          if (s->paused) {
            mjv_applyPerturbPose(v->model, d, &v->perturb, 1);
            mj_forward(m, d);
            sync_bodies(*this, *s);
          }
        } else {
          v->authored_camera_active = false;
          mjv_moveCamera(v->model, mouse, dx, dy, &v->camera);
        }
        return {};
      }
      if (action == "select") {
        double x = cmd.get("x", .5), y = cmd.get("y", .5),
               aspect = cmd.get("aspect", 1.);
        if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(aspect) ||
            aspect <= 0)
          return "Invalid picking coordinates";
        mjtNum point[3];
        int geom = -1, flex = -1, skin = -1;
        int body = mjv_select(v->model, f->data, &f->option, aspect, x, y,
                              &f->scene, point, &geom, &flex, &skin);
        v->cancel(*s);
        int button = cmd.get("button", 1);
        if (button == 2) {
          if (body >= 0) {
            v->authored_camera_active = false;
            mju_copy(v->camera.lookat, point, 3);
            if (bool(cmd.get("control", false)) && body > 0) {
              v->camera.type = mjCAMERA_TRACKING;
              v->camera.trackbodyid = body;
            }
          }
        } else {
          v->perturb.select = std::max(0, body);
          v->perturb.flexselect = -1;
          v->perturb.skinselect = -1;
          if (body >= 0) {
            mjtNum local[3];
            mju_sub3(local, point, f->data->xpos + 3 * body);
            mju_mulMatTVec(v->perturb.localpos, f->data->xmat + 9 * body, local,
                           3, 3);
          }
        }
        return {};
      }
      if (action == "parent") {
        v->cancel(*s);
        if (v->perturb.select > 0)
          v->perturb.select = m->body_parentid[v->perturb.select];
        return {};
      }
      if (action == "perturb_begin") {
        if (v->perturb.select <= 0)
          return "Select a body first";
        int mode = cmd.get("mode", int(mjPERT_TRANSLATE));
        if (mode != mjPERT_TRANSLATE && mode != mjPERT_ROTATE)
          return "Invalid perturbation";
        v->cancel(*s);
        mjv_initPerturb(v->model, d, &f->scene, &v->perturb);
        v->perturb.active = mode;
        return {};
      }
      if (action == "pause") {
        v->cancel(*s);
        s->paused = bool(cmd.get("value", !s->paused));
        s->accumulator = 0;
        if (!s->paused)
          v->scrub = 0;
        return {};
      }
      if (action == "history_back" || action == "history_forward" || action == "history_seek") {
        if (s->pending_step_request)
          return "Previous simulation step still pending";
        v->cancel(*s);
        if (action == "history_seek") {
          int offset = cmd.get("offset", 0);
          if (offset > 0 || offset < 1 - v->history_count)
            return "History offset out of range";
          s->paused = true;
          v->scrub = offset;
        } else if (action == "history_back") {
          s->paused = true;
          v->scrub = std::max(v->scrub - 1, 1 - v->history_count);
        } else {
          if (!s->paused)
            return "Pause before stepping";
          if (v->scrub < 0)
            v->scrub++;
          else {
            s->single_steps = 1;
            s->pending_step_request = r.request;
            s->skip_tick = false;
            deferred = true;
            return {};
          }
        }
        if (v->history_count) {
          int i = (v->history_cursor + v->scrub + v->history_capacity) %
                  v->history_capacity;
          mj_setState(m, d, v->history.data() + size_t(i) * v->state_size,
                      mjSTATE_INTEGRATION);
          mj_forward(m, d);
          sync_bodies(*this, *s);
        }
        return {};
      }
      if (action == "key_load" || action == "key_save") {
        int key = cmd.get("id", 0);
        if (key < 0 || key >= m->nkey)
          return "No such keyframe in the current model";
        v->key = key;
        if (action == "key_save")
          mj_setKeyframe(m, d, key);
        else {
          v->cancel(*s);
          mj_resetDataKeyframe(m, d, key);
          mj_forward(m, d);
          sync_bodies(*this, *s);
          v->add_history(*s);
        }
        return {};
      }
      if (action == "ctrl_noise") {
        double scale = cmd.get("std", v->noise_std), rate = cmd.get("rate", v->noise_rate);
        if (!std::isfinite(scale) || !std::isfinite(rate) || scale < 0 || scale > 1 || rate < 0 || rate > 4)
          return "Control noise requires scale 0..1 and rate 0..4";
        v->noise_std = scale;
        v->noise_rate = rate;
        return {};
      }
      if (action == "threads") {
        int count = cmd.get("value", 0);
        if (count < 0 || count > 10)
          return "Number of solver workers must be 0..10";
        mju_threadpool(d, count);
        v->num_threads = count;
        return {};
      }
      if (action == "pause_update") {
        v->pause_update = bool(cmd.get("enabled", false));
        return {};
      }
      if (action == "profiler") {
        v->profiler_enabled = bool(cmd.get("enabled", true));
        return {};
      }
      if (action == "speed") {
        int delta = cmd.get("delta", 0);
        v->speed_index = std::clamp(v->speed_index + delta, 0, 30);
        s->viewer_speed = kSpeeds[v->speed_index] / 100;
        return {};
      }
      if (action == "align") {
        v->authored_camera_active = false;
        int fixed = v->model->vis.global.cameraid;
        if (fixed >= 0 && fixed < m->ncam) {
          v->camera.type = mjCAMERA_FIXED;
          v->camera.fixedcamid = fixed;
        } else
          mjv_defaultFreeCamera(v->model, &v->camera);
        v->seeded = true;
        return {};
      }
      if (action == "track_body") {
        String name = cmd.get("name", String());
        int body = mj_name2id(m, mjOBJ_BODY, name.utf8().get_data());
        if (body <= 0)
          return "Tracking target no longer exists";
        v->authored_camera_active = false;
        v->camera.type = mjCAMERA_TRACKING;
        v->camera.trackbodyid = body;
        return {};
      }
      if (action == "camera") {
        int i = cmd.get("id", 0);
        if (i < 0 || i >= m->ncam + 2)
          return "Invalid camera";
        if (i == 1 && v->perturb.select <= 0)
          return "Select a body to track";
        v->authored_camera_active = false;
        if (i == 0)
          v->camera.type = mjCAMERA_FREE;
        else if (i == 1) {
          v->camera.type = mjCAMERA_TRACKING;
          v->camera.trackbodyid = v->perturb.select;
        } else {
          v->camera.type = mjCAMERA_FIXED;
          v->camera.fixedcamid = i - 2;
        }
        return {};
      }
      if (action == "cycle_camera") {
        if (!m->ncam)
          return {};
        v->authored_camera_active = false;
        int delta = cmd.get("delta", 1), i = v->camera.type == mjCAMERA_FIXED
                                                 ? v->camera.fixedcamid
                                                 : (delta > 0 ? -1 : 0);
        i = (i + delta + int(m->ncam)) % int(m->ncam);
        v->camera.type = mjCAMERA_FIXED;
        v->camera.fixedcamid = i;
        return {};
      }
      if (action == "frame" || action == "label") {
        int &value = action == "frame" ? v->option.frame : v->option.label;
        int count = action == "frame" ? int(mjNFRAME) : int(mjNLABEL);
        int n = cmd.get("value", (value + 1) % count);
        if (n < 0 || n >= count)
          return "Invalid visualization enum";
        value = n;
        return {};
      }
      if (action == "vis" || action == "rnd") {
        int i = cmd.get("id", -1);
        bool vis = action == "vis";
        int count = vis ? int(mjNVISFLAG) : int(mjNRNDFLAG);
        if (i < 0 || i >= count)
          return "Invalid flag";
        if (!v->native_backend &&
            (!vis || i == mjVIS_CONVEXHULL || i == mjVIS_TEXTURE ||
             i == mjVIS_ACTIVATION || i == mjVIS_ISLAND ||
             i == mjVIS_TRANSPARENT || i == mjVIS_PERTOBJ))
          return "MuJoCo surface effect unavailable in Godot renderer";
        if (vis && !flag_supported(i, m))
          return "Current model has no flex/skin";
        auto *p = vis ? v->option.flags : v->render_flags;
        p[i] = bool(cmd.get("value", !p[i]));
        return {};
      }
      if (action == "group") {
        auto *p = group(*v, cmd.get("name", String()));
        int i = cmd.get("id", -1);
        if (!p || i < 0 || i >= mjNGROUP)
          return "Invalid group";
        p[i] = bool(cmd.get("value", !p[i]));
        return {};
      }
      if (action == "visual") {
        String field = cmd.get("name", String());
        String error = set_visual(*v, cmd);
        if (error.is_empty() && (field == "global.fovy" || field == "global.orthographic" ||
            field == "map.znear" || field == "map.zfar" ||
            field == "stat.extent"))
          v->authored_camera_active = false;
        if (error.is_empty() &&
            String(cmd.get("name", String())) == "global.orthographic")
          v->camera.orthographic = v->model->vis.global.orthographic;
        return error;
      }
      if (action == "tree_depth") {
        v->option.bvh_depth = std::clamp(int(cmd.get("value", 0)), 0, 20);
        return {};
      }
      if (action == "joint") {
        int i = cmd.get("id", -1);
        double x = cmd.get("value", 0.);
        if (!s->paused)
          return "Joint editing requires pause";
        if (i < 0 || i >= m->njnt ||
            (m->jnt_type[i] != mjJNT_SLIDE && m->jnt_type[i] != mjJNT_HINGE) ||
            !std::isfinite(x))
          return "Invalid scalar joint";
        if (m->jnt_limited[i] &&
            (x < m->jnt_range[2 * i] || x > m->jnt_range[2 * i + 1]))
          return "Joint outside range";
        v->cancel(*s);
        d->qpos[m->jnt_qposadr[i]] = x;
        mj_forward(m, d);
        sync_bodies(*this, *s);
        return {};
      }
      if (action == "control") {
        int i = cmd.get("id", -1);
        double x = cmd.get("value", 0.);
        if (i < 0 || i >= m->nu || !std::isfinite(x))
          return "Invalid actuator";
        if (m->actuator_group[i] >= 0 && m->actuator_group[i] <= 30 &&
            (m->opt.disableactuator & (1 << m->actuator_group[i])))
          return "Actuator group disabled by design";
        if (m->actuator_ctrllimited[i] &&
            (x < m->actuator_ctrlrange[2 * i] ||
             x > m->actuator_ctrlrange[2 * i + 1]))
          return "Control outside range";
        d->ctrl[i] = x;
        return {};
      }
      if (action == "clear_control") {
        mj_resetCtrl(m, d);
        return {};
      }
      if (action == "equality") {
        int i = cmd.get("id", -1);
        if (i < 0 || i >= m->neq)
          return "Invalid equality";
        d->eq_active[i] = bool(cmd.get("value", true));
        mj_forward(m, d);
        return {};
      }
      if (action == "capture_snapshot") {
        v->snapshot.resize(v->state_size);
        mj_getState(m, d, v->snapshot.data(), mjSTATE_INTEGRATION);
        return {};
      }
      if (action == "restore_snapshot") {
        if (v->snapshot.size() != size_t(v->state_size))
          return "No snapshot for this model revision";
        v->cancel(*s);
        mj_setState(m, d, v->snapshot.data(), mjSTATE_INTEGRATION);
        mj_forward(m, d);
        sync_bodies(*this, *s);
        return {};
      }
      if (action == "reset_initial" || action == "step") {
        v->cancel(*s);
        world_commands.push_back(
            {r.request, r.space, action, int(cmd.get("count", 1))});
        deferred = true;
        return {};
      }
      if (action == "copy_state") {
        result["text"] = copy_key(*s, bool(cmd.get("precise", false)));
        return {};
      }
      if (action == "copy_camera") {
        if (!f)
          return "Displayed frame expired";
        auto c = mjv_averageCamera(f->scene.camera, f->scene.camera + 1);
        mjtNum forward[3], up[3], right[3];
        mju_f2n(forward, c.forward, 3);
        mju_f2n(up, c.up, 3);
        mju_cross(right, forward, up);
        char xml[500];
        std::snprintf(xml, sizeof(xml),
                      "<camera pos=\"%.3f %.3f %.3f\" xyaxes=\"%.3f %.3f %.3f "
                      "%.3f %.3f %.3f\"/>\n",
                      c.pos[0], c.pos[1], c.pos[2], right[0], right[1],
                      right[2], up[0], up[1], up[2]);
        result["text"] = String::utf8(xml);
        return {};
      }
      if (action == "save_xml" || action == "save_mjb") {
        String path = cmd.get("path", String());
        if (path.is_empty() || path.contains("\n"))
          return "Choose an output path";
        PackedByteArray bytes;
        String xml;
        if (action == "save_xml") {
          xml = export_xml(*s);
          if (xml.is_empty())
            return "Committed design XML is unavailable for this world";
        } else {
          mjtSize size = mj_sizeModel(m);
          if (size <= 0 || size > std::numeric_limits<int>::max())
            return "Model binary exceeds the supported export buffer";
          bytes.resize(size);
          mj_saveModel(m, nullptr, bytes.ptrw(), size);
        }
        Ref<FileAccess> file = FileAccess::open(path, FileAccess::WRITE);
        if (file.is_null())
          return "Cannot write output file";
        if (action == "save_xml")
          file->store_string(xml);
        else
          file->store_buffer(bytes);
        file->flush();
        if (file->get_error() != OK)
          return "Could not complete model export";
        result["path"] = path;
        return {};
      }
      if (action == "print_model" || action == "print_data") {
        String path = cmd.get("path", String());
        if (path.is_empty() || path.contains("\n"))
          return "Choose an output path";
        String real = ProjectSettings::get_singleton()->globalize_path(path);
        FILE *test = std::fopen(real.utf8().get_data(), "wb");
        if (!test)
          return "Cannot write output file";
        std::fclose(test);
        if (action == "print_model")
          mj_printModel(m, real.utf8().get_data());
        else
          mj_printData(m, d, real.utf8().get_data());
        result["path"] = path;
        return {};
      }
      if (action == "logging") {
        auto cfg = mju_getLogConfig();
        cfg.logto_console = bool(cmd.get("console", cfg.logto_console));
        cfg.logto_file = bool(cmd.get("file", cfg.logto_file));
        cfg.topics = int(cmd.get("topics", cfg.topics)) & ((1 << mjNTOPIC) - 1);
        String path = cmd.get("path", String::utf8(cfg.logfile));
        String full = ProjectSettings::get_singleton()->globalize_path(path);
        if (full.utf8().length() >= int(sizeof(cfg.logfile)))
          return "Log path too long";
        if (cfg.logto_file) {
          FILE *file = std::fopen(full.utf8().get_data(), "ab");
          if (!file)
            return "Cannot open log output file";
          std::fclose(file);
        }
        std::snprintf(cfg.logfile, sizeof(cfg.logfile), "%s",
                      full.utf8().get_data());
        mju_setLogConfig(cfg);
        return {};
      }
      return "Unknown viewer action";
    };
    String error = apply();
    auto *owner = space(r.space);
    if (owner && owner->viewer && int64_t(owner->revision) == r.revision) {
      auto &v = *owner->viewer;
      if (auto *f = find_frame(v, r.frame))
        f->pins = std::max(0, f->pins - 1);
      if (v.presented)
        scene_viewer_ack(r.space, r.revision, v.presented);
    }
    if (deferred && error.is_empty())
      continue;
    result["success"] = error.is_empty();
    result["error"] = error;
    auto *s = space(r.space);
    if (s && s->data) {
      result["time"] = s->data->time;
      result["paused"] = s->paused;
    }
    std::lock_guard<std::mutex> lock(requests_mutex);
    world_command_results[r.request] = result;
  }
}
bool MjPhysicsServer3D::scene_viewer_ack(const RID &rid, int64_t revision,
                                         int64_t frame) {
  if (!main_thread())
    return false;
  auto *s = space(rid);
  if (!s || !s->viewer || int64_t(s->revision) != revision)
    return false;
  auto &v = *s->viewer;
  if (!find_frame(v, frame) || frame < v.presented)
    return false;
  v.presented = frame;
  while (v.frames.size() > 1 && v.frames.front()->id < frame &&
         v.frames.front()->pins == 0) {
    v.spare_frames.push_back(std::move(v.frames.front()));
    v.frames.pop_front();
  }
  return true;
}
Dictionary MjPhysicsServer3D::scene_viewer_frame(const RID &rid, int64_t known,
                                                 const Dictionary &opts) {
  Dictionary out;
  auto fail = [&](const char *why) {
    out["error"] = why;
    return out;
  };
  if (!main_thread() || flushing)
    return fail("Viewer requires main-thread physics outside callbacks");
  auto *s = space(rid);
  if (!s)
    return fail("Viewer world unavailable");
  if (s->dirty || s->design_blocked) {
    out["pending"] = true;
    return out;
  }
  auto *v = ensure(*s);
  if (!v)
    return fail("Viewer requires a rigid model within its 256 MiB CPU "
                "scene/history budget");
  v->native_backend = String(opts.get("backend", String("godot"))) == "native";
  v->profiler_enabled = bool(opts.get("profiler", false));
  if (v->frames.size() >= 3) {
    out["pending"] = true;
    out["status"] = "Waiting for displayed frame acknowledgement";
    return out;
  }
  std::unique_ptr<MjViewerFrame> frame;
  if (!v->spare_frames.empty()) {
    frame = std::move(v->spare_frames.front());
    v->spare_frames.pop_front();
  } else
    frame = std::make_unique<MjViewerFrame>(v->model);
  if (!frame->data)
    return fail("Cannot allocate frozen visualization data");
  frame->id = v->next_frame++;
  mjv_copyData(frame->data, s->model, s->data);
  if (v->perturb.active && v->last_wrench_body > 0 &&
      v->last_wrench.size() == 6)
    for (int i = 0; i < 6; i++)
      frame->data->xfrc_applied[6 * v->last_wrench_body + i] +=
          v->last_wrench[i];
  frame->option = v->option;
  if (!v->native_backend)
    frame->option.flags[mjVIS_CONVEXHULL] = 0;
  mjv_updateScene(v->model, frame->data, &frame->option, &v->perturb,
                  &v->camera, mjCAT_ALL, &frame->scene);
  auto &scene = frame->scene;
  std::memcpy(scene.flags, v->render_flags, sizeof(scene.flags));
  scene.stereo = mjSTEREO_NONE;
  auto cam = v->authored_camera_active
                 ? v->authored_camera
                 : mjv_averageCamera(scene.camera, scene.camera + 1);
  scene.camera[0] = scene.camera[1] = cam;
  if (v->authored_camera_active)
    for (int i = 0; i < scene.nlight; i++)
      if (scene.lights[i].headlight)
        for (int k = 0; k < 3; k++) {
          scene.lights[i].pos[k] = cam.pos[k];
          scene.lights[i].dir[k] = cam.forward[k];
        }
  out["scene_geoms"] = packed(scene.geoms, scene.ngeom);
  out["scene_lights"] = packed(scene.lights, scene.nlight);
  out["scene_cameras"] = packed(scene.camera, 2);
  out["scene_flags"] = packed(scene.flags, mjNRNDFLAG);
  out["scene_visual"] = packed(&v->model->vis, 1);
  out["scene_stat"] = packed(&v->model->stat, 1);
  out["scene_abi"] = mj_version();
  out["space"] = int64_t(rid.get_id());
  out["revision"] = int64_t(s->revision);
  out["frame_id"] = frame->id;
  out["time"] = s->data->time;
  out["ngeom"] = int(s->model->ngeom);
  out["paused"] = s->paused;
  out["speed_percent"] = kSpeeds[v->speed_index];
  out["selected_body"] = v->perturb.select;
  out["selected_name"] = object_name(s->model, mjOBJ_BODY, v->perturb.select);
  out["perturb_active"] = v->perturb.active;
  out["history_count"] = v->history_count;
  out["history_offset"] = v->scrub;
  out["history_bytes"] = int64_t(v->history.size() * sizeof(mjtNum));
  out["has_snapshot"] = !v->snapshot.empty();
  out["key"] = v->key;
  out["noise_std"] = v->noise_std;
  out["noise_rate"] = v->noise_rate;
  out["num_threads"] = v->num_threads;
  out["pause_update"] = v->pause_update;
  out["settings"] = settings(*v);
  Vector3 forward = vector(cam.forward).normalized(),
          up = vector(cam.up).normalized(),
          right = forward.cross(up).normalized();
  Basis basis;
  basis.set_column(0, right);
  basis.set_column(1, up);
  basis.set_column(2, -forward);
  Dictionary camera;
  camera["type"] = v->camera.type;
  camera["fixed_id"] = v->camera.fixedcamid;
  if (v->camera.type == mjCAMERA_FIXED)
    camera["target"] =
        object_name(v->model, mjOBJ_CAMERA, v->camera.fixedcamid);
  if (v->camera.type == mjCAMERA_TRACKING)
    camera["target"] = object_name(v->model, mjOBJ_BODY, v->camera.trackbodyid);
  camera["transform"] = Transform3D(basis, vector(cam.pos));
  camera["orthographic"] = bool(cam.orthographic);
  camera["near"] = double(cam.frustum_near);
  camera["far"] = double(cam.frustum_far);
  camera["size"] = double(cam.frustum_top - cam.frustum_bottom);
  camera["width"] = double(cam.frustum_width);
  camera["offset"] =
      Vector2(cam.frustum_center, (cam.frustum_top + cam.frustum_bottom) / 2);
  camera["fov"] = 2 *
                  std::atan((cam.frustum_top - cam.frustum_bottom) /
                            (2 * cam.frustum_near)) *
                  180 / Math_PI;
  out["camera"] = camera;
  Dictionary stats;
  stats["viewer_scene_slots"] =
      int(v->frames.size() + v->spare_frames.size() + 1);
  stats["time"] = s->data->time;
  stats["contacts"] = s->data->ncon;
  stats["constraints"] = s->data->nefc;
  stats["arena_used_bytes"] = int64_t(s->data->maxuse_arena);
  stats["arena_bytes"] = int64_t(s->data->narena);
  stats["profiler"] = v->profiler;
  stats["timing_available"] = mjcb_time == timer_ms;
  Array timings = v->profiler.get("timing_ms", Array());
  stats["cpu_ms"] = s->paused ? v->paused_cpu_ms : timings.is_empty() ? 0.0 : double(timings[0]);
  int info_iterations = 0;
  double info_error = 0;
  int info_islands = std::max(1, std::min(s->data->nisland, mjNISLAND));
  for (int k = 0; k < info_islands; k++) {
    int n = std::min(s->data->solver_niter[k], mjNSOLVER);
    info_iterations += s->data->solver_niter[k];
    if (n) {
      const auto &t = s->data->solver[k * mjNSOLVER + n - 1];
      double error = std::min(t.improvement, t.gradient);
      if (error == 0)
        error = std::max(t.improvement, t.gradient);
      info_error = std::max(info_error, error);
    }
  }
  stats["solver_log_error"] = s->paused ? std::log10(std::max(mjMINVAL, info_error)) : double(v->profiler.get("solver_log_error", -15.0));
  stats["solver_iterations"] = s->paused ? info_iterations : int(v->profiler.get("iterations", 0));
  stats["islands"] = s->data->nisland;
  stats["islands_enabled"] = !(s->model->opt.disableflags & mjDSBL_ISLAND);
  stats["energy_enabled"] = bool(s->model->opt.enableflags & mjENBL_ENERGY);
  stats["energy"] = s->data->energy[0] + s->data->energy[1];
  stats["fwdinv_enabled"] = bool(s->model->opt.enableflags & mjENBL_FWDINV);
  Array fwdinv;
  fwdinv.append(s->data->solver_fwdinv[0]);
  fwdinv.append(s->data->solver_fwdinv[1]);
  stats["fwdinv"] = fwdinv;
  out["stats"] = stats;
  PackedInt32Array visible;
  Array decorations;
  bool godot = String(opts.get("backend", String("godot"))) == "godot";
  for (int i = 0; i < scene.ngeom; i++) {
    auto &g = scene.geoms[i];
    if (g.objtype == mjOBJ_GEOM && g.objid >= 0)
      visible.append(g.objid);
    if (godot && ((g.objtype != mjOBJ_GEOM) || (g.label[0]))) {
      Dictionary x;
      x["type"] = g.type;
      x["transform"] = Transform3D(matrix(g.mat), vector(g.pos));
      x["size"] = Vector3(g.size[0], g.size[1], g.size[2]);
      x["color"] = Color(g.rgba[0], g.rgba[1], g.rgba[2], g.rgba[3]);
      x["label"] = String::utf8(g.label);
      x["model_geom"] = g.objtype == mjOBJ_GEOM;
      decorations.append(x);
    }
  }
  out["visible_geoms"] = visible;
  out["decorations"] = decorations;
  if (known != int64_t(s->revision))
    out["catalog"] = catalog(*s, opts.get("backend", String("godot")));
  if (bool(opts.get("inspect", false)))
    out["inspect"] = inspect(*s, opts);
  v->frames.push_back(std::move(frame));
  return out;
}
} // namespace godot
