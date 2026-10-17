# Unverified native backend handoff

This development branch has passed the cloud checks in
[native-backend-validation.md](native-backend-validation.md), but is NOT
independently accepted by dot and must not be merged into main yet.

Base: 88eb9ef7421b2aeca584bfcecac3ac9afa969a4b. Godot 4.7.2 .NET, MuJoCo 3.16.0, Linux only.

The original draft at `8c0757753bba7820a345077d9c94b17ed775fd42` compiled in
the dot environment but exited 139 around the first physics frame. Cloud GDB
reproduced this in floating-point ostream formatting; isolating the static C++
runtime's ELF symbols fixes it. A separate reproducible import crash came from
documentation probing an unowned direct state's `step` property. Server-owned
classes now use abstract registration. This was distinct from the historical
baseline import timing issue. Ray results also now carry the engine object
pointer, rather than the godot-cpp wrapper pointer.

The original 44 checks and 25 added primitive/ownership checks passed three
repetitions each (207 checks, six processes) against the fixed backend. The
built-in physics negative control passes 42 behavior checks and fails exactly
the two backend identity checks. MjWorld and all three G1 binding suites also
passed. No visual acceptance has been completed.

Preserve MjWorld compatibility and the G1 C++, GDScript and C# regression suite. Use isolated build/output directories; do not overwrite known-good addon binaries before acceptance.
