# Private query witness narrowphase

This directory contains the minimal MPR/vector/support subset of libccd at
`7931e764a19ef6b21b443376c699bbc9c6d4fba8` (v2.1), the same revision used by
MuJoCo 3.16.0. Upstream: https://github.com/danfis/libccd/tree/7931e764a19ef6b21b443376c699bbc9c6d4fba8/src
The original BSD license and copyright notices are retained in `BSD-LICENSE`
and each source file. No downloads or external libccd runtime are required.

`mpr_witness.c` derives from upstream `mpr.c` with these local changes:

- Replace the public entry points with private `gmj_ccdMPRWitness`.
- Keep the converged portal's original per-shape support vertices.
- Compute barycentric weights of the origin's closest point on the portal
  triangle (or the closest edge for a degenerate triangle), and apply the same
  weights to both shapes' original support vertices. Return both witnesses.
- Segment/touch portal cases return the original support pair directly.
- Reconstruct depth, displacement and midpoint from those witnesses, instead
  of treating upstream's estimated contact position as a witness midpoint.

`ccd/config.h` fixes double precision and prefixes the few global vector/support
symbols, avoiding interposition with MuJoCo's separate internal libccd copy.
Other files are upstream support code (trailing whitespace normalized).

The caller provides analytic support functions for existing Godot primitives,
uses a strictly interior reference point to seed MPR without moving geometry,
validates both witnesses against the original analytic surfaces, and derives
rest normals from the target surface's normal cone. This is private query code:
it does not replace or modify MuJoCo simulation narrowphase, implement new
shape types, or claim globally minimal penetration recovery/continuous sweep.
