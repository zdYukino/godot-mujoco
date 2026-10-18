# Stability gate (Linux, fixed 4.7.2 .NET / MuJoCo 3.16.0)

This suite records results; it does not promote a baseline. The target is remote
commit `2a178101b9b72f9064f647291002da9d2f52913f`, tree
`cd9506478e9fb7fe651ccd7ac3de05d41225fd32`.

Before execution, freeze tracked source hashes, native binary hash, engine hash,
versions and exact commands. Every cold trial gets a new project with no `.godot`
and private XDG data/config/cache directories. No cached retries. At most two
processes run concurrently, each at nice 10 with at most two allowed CPUs.

Planned matrix:

| Category | Planned coverage | Gate |
| --- | --- | --- |
| Cold import, light load | 20 sequential project-helper trials; 3 official `--headless --editor --import` controls | Every process exit 0, no script/native errors or leaks; any 139 fails gate |
| Cold import, controlled concurrency | 10 helper trials in pairs, separate directories | Same gate; no shared project or XDG cache |
| Editor lifecycle | 5 fresh projects: helper import then full real-renderer editor acceptance and shutdown | Imports tracked separately; 116 acceptance checks, clean process exit; renderer startup diagnostics classified explicitly |
| Portable migration | 3 full official runtime runners and 3 asset runners, new OUT each time | Both import phases recorded, original paths unavailable; all assertions and exits pass |
| Runtime pressure | 3 processes × 30 insert/remove cycles and 10 same-node world reentries; missing-asset recovery in each cycle | Compatible live state retained, stale RID absent, no simulation warnings, recovery succeeds |

If repeated identical import crashes plus retained root-cause evidence make more
same-mode attempts redundant, stop that mode and mark remaining cases skipped
because of the demonstrated blocker (never passed). Continue independent runtime
and editor coverage only on explicitly identified successful fixture imports.
A GUI import cannot substitute for a failed headless import.

Final classification must separately state cold import, real editor lifecycle,
and runtime/migration outcomes. Even all-pass fresh samples do not erase earlier
139s. Do not merge main unless the overall gate is satisfied independently.

`runtime_followup.py --lifecycle EVIDENCE/lifecycle` records separately labeled
post-import pressure/C# coverage when fresh-XDG NuGet initialization blocks the
full runner. Source the established SDK environment for this follow-up; it does
not alter or overwrite the original failed trial records.

Use `editor_followup.py --source FROZEN_SOURCE --lifecycle EVIDENCE/lifecycle`
after the configured-SDK follow-up completes to separately cover portable editor
acceptance and saved-scene restart. Do not overlap these stages with the cold
matrix or pressure runs. Original runner failures remain failures.
