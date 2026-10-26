# Fixed 3.16 SDF interval contract and remaining certification work

This implementation is tied to MuJoCo 3.16.0, double mjtNum and the native,
plugin-free mesh octree representation. It does not use visual triangles as
an exact substitute for the compiled SDF, or claim that a projected stationary
surface point is a globally nearest point.

## Actual field and feasibility

The fixed [SDF engine source](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/engine/engine_collision_sdf.c)
selects an octree leaf with a 1e-8 box tolerance, interpolates eight stored
coefficients, and extends values outside the root by box projection/distance.
The projection moves qualifying coordinates 1e-6 inward. Native rounded
abs(p-center)-half, rather than an exact coordinate comparison, selects that
branch. An offset center can round an input one ULP inside to the boundary
while a different axis is outside. The implementation bounds both possibilities.

The fixed [octree construction](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/user/user_objects.cc)
contains hanging-node coefficient interpolation and optional smoothing.
The represented field is not simply exact mesh signed distance. A per-leaf
derivative magnitude can be bounded from coefficient differences divided by
cell widths; measured values exceed one. Root projection also produces a
measured ~1e-6 value change over a 2e-12 point separation. Therefore a global
unit-Lipschitz constant cannot certify these sweeps.

The public model arrays are sufficient for a piecewise interval enclosure:
no missing public temporal TOI API is invented. This establishes a viable
bounded implementation, not a guarantee that every boundary converges within
the resource budget.

## Scalar enclosure

For each leaf, use native rounded low/high/denominator. A trilinear polynomial
is multi-affine: its extrema over a coordinate box occur at its eight corners.
Outward-rounded arithmetic encloses coefficient interpolation and a gamma_128
allowance encloses native weight/product/sum roundoff, including an absolute
subnormal guard. Leaf boxes include the native selection tolerance plus an
arithmetic guard. All possibly selected leaves contribute to the range.
Exterior projection, its rounded branch condition, cancellation error and
box-distance extension are included. An unreliable exterior shift rejects.

Inside the root, an arbitrary finite affine plane a.x may tighten the bound.
Subtract it from the leaf polynomial and enclose that residual at all eight
box corners. Add the minimum of a.x over the entire swept support volume.
This bounds the intersection of that volume with the leaf even when the
support point is outside the leaf. The plane need not be an SDF tangent or
closest plane. This tightening is disabled across exterior projection.
The independent native test samples 12000 general points and 6400 points
inside sphere support volumes, plus 108 root and 80 offset-ULP probes.

## Joint cell/query sign certificate

A cell AABB and a query can each reach low polynomial values at different
points. Their independent minima need not describe their intersection.
For a leaf and current clipped cell box B, choose an arbitrary affine plane
a.x, recentered for efficiency at B's center. Its derivative estimate is
not used as a proof. Outward interpolation gives a residual lower bound r
including native evaluation roundoff. Therefore all potentially nonpositive
points lie in P = B intersect {a.x + r <= 0}.

The implementation retains all possibly inside box corners and computes all
12 box-edge/plane intersections with outward interval arithmetic. Every
intersection vertex is enclosed by a coordinate box; the convex hull of
those boxes encloses P. An uncertain/zero denominator abandons this
optimization. GJK separation of the query from that enclosing hull, with
the existing geometric/error guard, certifies no nonpositive point in the
joint domain. This is recorded separately as Range.shape_positive, not
invented as a numeric scalar lower value. It is disabled across root exterior
projection. Numerical clipping cannot shrink the candidate region.

The native analytic counterexample uses F=1.12-x-y, a radius-1.5 sphere at
(-1,0,0), and cell box [0,.5] x [0,1] x [-.05,.05]. The unconstrained sphere
minimum is negative, while the joint minimum is 0.0019660112501052041.
The final native test also checks 20809 points from 200 random trilinear
fields/cell/sphere configurations; 100 cases receive the positive sign
certificate. Sampled checks support review but are not a formal proof.

## Geometry enclosure

The scalar polynomial enclosure alone does not cover geometry errors.
Canonical double quaternion rotation defines the backend query orientation.
A per-axis envelope uses

E = gamma_256 * (1 + sum(abs(query origin)) + sum(abs(target origin))
                  + 4*sum(query sizes) + 3*margin
                  + max(abs(t0),abs(t1))*sum(abs(full original motion))).

The scale is computed outward. Direction normalization is scaled before
support evaluation to avoid overflow/underflow. Domain bounds avoid tiny
features relative to E and unreliable root-projection cancellation.
The support AABB expands by E, GJK lower planes require sqrt(3)E clearance,
and inscribed support tetrahedra require that strict interior guard.
A negative-field spatial witness is bounded over its E-neighborhood.
Contact membership shrinks by the same geometric guard; actual negative field
evaluation maps the same world witness back through the native target transform.
Full original origin/motion magnitudes remain in E after cancellation.

This bound and the complete implementation still require independent review.
Passing sampled probes is evidence, not a formal proof or independent approval.

## Path and witness contract

At fixed orientation, the union of a translated convex primitive over a time
interval is its Minkowski sum with the motion segment. Only a positive-field
separation certificate over that entire swept volume discards an interval.
Time intervals are processed in order; the last proven prefix remains clear.
Actual contact poses supply upper bounds. A pose sample, ray march or a
clear midpoint never supplies a miss certificate, including nonconvex
multiple-entry paths.

A returned result needs both the continuous pose and independently rounded
Godot Float32 pose certified at safe/unsafe fractions. Large world coordinates
may require widening those candidates by measured position/product ULPs.
Every widened candidate is still checked. The status reports returned width.

SDF witness projection supplies a local surface pair only after actual field
and original query-surface checks. Deep containment uses a negative point
inside the query plus an original-surface chord. Reported normal is the target
field gradient, not an arbitrary chord direction. These are not globally
minimal penetration vectors. Unknown witness/zero-boundary cases fail the
whole request with observable status.

The search plus endpoint checks uses a 2-second checkpoint deadline; bounded GJK/contact calls are not preempted, so this is not a strict wall-clock upper bound. Cache build is
separate. A coarse-enclosure experiment retained the safe prefix and actual
upper but failed final endpoint certification / width bounds on the two
remaining cases. It was withdrawn, not promoted to supported behavior.

## Remaining exact cases and next necessary design

The final sdf_terrain_edges.gd suite has 21 passed checks and one unresolved
path. The earlier stair_edge countercase now passes, including original-surface
rest information and normal validation. The remaining case is:
- rough_oblique: sphere radius .04 at (2.3,1,-.6), motion (1.2,-2,1.2).

The path reaches an unresolved temporal refinement interval around
t=0.40095715684853 at depth 48, with time/node budget not exhausted. This is
not a proven miss, and neither an exact tangent nor a field discontinuity has
been established as its cause. A local contact optimizer and interior-point
bridge did not close it and were withdrawn; their source/logs remain outside
the working tree under the GTR evidence experiments directories.

This is an unresolved certification limitation, not proof that the engine
makes the path impossible. Enlarging budgets does not address this final
interval's sign/endpoint uncertainty.

sdf_thin.gd additionally reports exact touch_inward, touch_away and graze
as unresolved. Its eight functional thin/high-speed checks are separate from
the three observable-error contract checks. They must not be counted as eleven
successful geometric queries.

Closing these boundaries needs a certified primitive-constrained polynomial
root/interval-Newton or equivalent optimization solver with robust feature,
leaf and root-branch handling, integrated with witness extraction. A separate
product decision is required on requested TOI bracket accuracy, exact-touch
semantics and whether a bounded "unknown" is acceptable to callers. A finite
budget cannot by itself guarantee strict sign separation at exact tangency.
Neither extra wall time, source-triangle replacement nor unverified midpoint
bisection closes that requirement. Dynamic CCD and angular interpolation are
separate features and remain outside this public translation query.
