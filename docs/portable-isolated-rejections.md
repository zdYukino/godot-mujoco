# Portable negative-case isolation — 2026-10-18

Follow-up to `1df375abfa5195f3d3b323ced3e413a7ca9c6a88`, limited to test design.
No product API, native binary, engine, F5/Vulkan or cold-import changes.

The two deliberately invalid world configurations formerly shared the
`recovery-integrity.log` process with normal package-integrity checks. Its expected
ERRORs consequently failed the strict whole-log gate. They now execute as **two
independent Godot processes**, one case per process. Normal package-integrity
checks remain in the original process and must emit no ERROR or leak.

`world_rejections.py` retains each process's complete combined stdout/stderr in
`negative/missing_model.log` and `negative/ownership.log`. It records exact command,
exit status and assertion report in `negative/results.json`. For each case:

- Require exit 0, exactly one result report, the correct case ID, the complete
  assertion count, unique assertion names and every assertion passing.
- Require exactly one ERROR line, byte-for-byte matching that case's diagnostic.
  Additional, missing, changed or duplicate ERRORs fail. SCRIPT ERRORs also fail.
- Reject any leak or failed assertion; timeout (124), crash or other nonzero exit
  fails regardless of output markers. No log is deleted, sanitized or rewritten.

The missing-model process checks failure before space configuration, exact
`last_error`, no ownership claim, corrected re-entry with the original start mode,
loading all 29 G1 joints after recovery, and cleanup (6 assertions).

The ownership process starts a real paused G1 world and checks exact rejection of
the second owner, unchanged complete model state/world info (including revision,
time, controls and pause), unchanged owner after removing the failed entrant,
recovery after the first owner is disposed, robot reload and cleanup (8 assertions).

Product `push_error` behavior is preserved: these are intentionally invalid startup
configurations and existing diagnostic/structured-error contracts remain useful.
The fix is to test those contracts separately, not suppress application errors.
All normal-process logs still undergo the unconditional ERROR/leak gate. The suite
also requires both isolated negative-case audits to pass; the negative directory
is not a general error exemption.

## Verification

```
source /workspace/shared/tools/env.sh
OUT=/workspace/shared/validation/portable-isolated-rejections tests/portable_runtime/run_runtime.sh
python -m unittest discover -s tests/portable_runtime -p test_world_rejection_audit.py -v
bash -n tests/portable_runtime/run_runtime.sh
git diff --check
```

All commands exited **0**. The full portable runner used a new OUT, including fresh
initial/relocated import, original project renamed offline and original assets
removed from the relocated project. .NET used the previously approved precise write
permission for `/home/agent/.dotnet/corefx/Runtime/SharedMemory`.

Results: runtime 30/30, relocated runtime 30/30, live edit 84/84, editor 9/9,
normal integrity 41/41, isolated negatives 6/6 + 8/8; C# build/control and editor
scene restart passed. **Every normal-process log has zero ERROR and zero leak.**
This run's imports succeeded; no retry was used and cold-import stability is not
claimed.

Two audit contract unit tests cover both exact valid cases and 14 false-green
mutations/statuses: unrelated/script errors, leaks, missing/changed/duplicate
expected error, missing/duplicate report, failed assertion/result, wrong case,
nonzero exit, timeout and crash. Each invalid case is rejected.

Portable evidence:

- [Full missing-model process log](evidence/portable-isolated-rejections/missing_model.log)
- [Full ownership process log](evidence/portable-isolated-rejections/ownership.log)
- [Negative commands, exits and assertion reports](evidence/portable-isolated-rejections/results.json)
- [Complete suite assertion results](evidence/portable-isolated-rejections/suite-results.json)
- [Normal-log hashes and strict audit](evidence/portable-isolated-rejections/normal-log-audit.json)

Earlier failed audits/logs remain in their original evidence directories. This
follow-up resolves their test-design issue; it does not retroactively reclassify
those runs. Dot's F5/Vulkan investigation and independent GUI acceptance remain
separate. Main is not modified.
