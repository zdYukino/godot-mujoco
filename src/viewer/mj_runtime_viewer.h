#pragma once
// MuJoCo 3.16 simulate adaptation. See UPSTREAM.md and LICENSE-MUJOCO.
#include <deque>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <memory>
#include <mujoco/mujoco.h>
#include <vector>
namespace godot {
struct MjSpace;
struct MjViewerFrame {
  int64_t id = 0;
  int pins = 0;
  mjData *data = nullptr;
  mjvOption option{}; // Visibility at presentation time, also used by picking.
  mjvScene scene{};
  MjViewerFrame(const mjModel *model);
  ~MjViewerFrame();
};
struct MjViewerState {
  uint64_t revision = ~uint64_t(0);
  int64_t next_frame = 1, presented = 0, sequence = 0;
  // Owned header/vis/stat, read-only arrays borrowed from the active revision.
  // Every caller runs on the physics main thread and validates that revision.
  // No model pointers enter a render packet. Destroy with delete, not
  // mj_deleteModel.
  mjModel *model = nullptr;
  mjvCamera camera{};
  mjvGLCamera authored_camera{};
  bool authored_camera_active = false;
  mjvOption option{};
  mjvPerturb perturb{};
  mjtByte render_flags[mjNRNDFLAG]{};
  std::deque<std::unique_ptr<MjViewerFrame>> frames;
  std::deque<std::unique_ptr<MjViewerFrame>> spare_frames;
  std::vector<mjtNum> history, snapshot;
  int state_size = 0, history_capacity = 0, history_count = 0,
      history_cursor = -1, scrub = 0;
  int speed_index = 0;
  int key = 0, num_threads = 0;
  double noise_std = 0, noise_rate = 0;
  double paused_cpu_ms = 0;
  bool pause_update = false;
  bool profiler_enabled = false;
  bool native_backend = false;
  // A bounded cancellation latch survives input/result queue saturation.
  int64_t cancel_sequence = 0;
  bool cancel_pending = false, release_pending = false;
  Dictionary profiler;
  mjTimerStat timers[mjNTIMER]{};
  std::vector<mjtNum> applied_wrench;
  std::vector<mjtNum> last_wrench;
  int last_wrench_body = 0;
  int wrench_body = 0;
  ~MjViewerState();
  void cancel(MjSpace &space);
  void add_history(MjSpace &space);
};
void gmj_viewer_before_step(MjSpace &space);
void gmj_viewer_update_paused(MjSpace &space);
void gmj_viewer_begin_batch(MjSpace &space);
void gmj_viewer_after_step(MjSpace &space);
void gmj_viewer_after_batch(MjSpace &space);
void gmj_viewer_invalidate(MjSpace &space);
void gmj_viewer_capture_snapshot(MjSpace &space);
godot::String gmj_viewer_restore_snapshot(MjSpace &space);
void gmj_viewer_install_timer();
void gmj_viewer_remove_timer();
} // namespace godot
