# Unverified native backend handoff

This development snapshot is NOT accepted and must not be merged into main until independently verified.

Base: 88eb9ef7421b2aeca584bfcecac3ac9afa969a4b. Godot 4.7.2 .NET, MuJoCo 3.16.0, Linux only.

The draft compiled in the dot environment. Runtime confirmed MjPhysicsServer3D identity and MuJoCo configuration, then exited 139 around the first physics frame after creating the floor and rigid body. Cause remains unknown. A fresh import also exited 139 despite the baseline frame-delay workaround. Do not conflate the runtime crash with the pre-existing first-import exit race.

Tests under tests/native_backend contain 44 checks; no passing native-backend run has been established. The built-in physics negative control passes behavior checks but fails the two backend identity checks. No visual acceptance has been completed.

Preserve MjWorld compatibility and the G1 C++, GDScript and C# regression suite. Use isolated build/output directories; do not overwrite known-good addon binaries before acceptance.
