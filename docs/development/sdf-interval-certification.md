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
separate. A historical, pre-finite-precision coarse-enclosure experiment retained the safe prefix and actual
upper but failed final endpoint certification / width bounds on the two
remaining cases. It was withdrawn, not promoted to supported behavior.

## Native branch domains

findOct selects children from the rounded coordinate
(p - rounded_vmin) / rounded_width < .5. EPS=1e-8 validates a node box;
it does not make overlapping child boxes interchangeable. Each traversal task
retains its ancestor-selected domain. Outward forward coordinate intervals
determine possible children, and a guarded split preimage clips each child's
domain. The 64-epsilon coordinate-scale guard covers subtraction/division
rounding; it is separate from the 16-epsilon node-box guard. A 120-probe native
branch suite includes ULP/EPS overlap and a near-split cell-range width check.
The earlier broad union was conservative but unnecessarily loose.

## Finite precision and candidate refinement

The user explicitly permits <=1mm spatial uncertainty. Default is 0.5mm,
configurable up to 1mm, relative to the compiled SDF path event:
|motion|*(tU-tL) + ePoseL + ePoseU <= requested_budget.
Each endpoint error includes separately bounded Float32 pose rounding and
the propagated arithmetic/transform envelope. All arithmetic forming the
reported budget is rounded outward. Large-coordinate quantization that
exceeds the requested budget causes an explicit failure.

The interval search alone advances a proven safe prefix. An actual interior
negative-field witness supplies a hit upper. Optional bounded upper probes and
sphere tangent-space surface refinement produce candidates only; every
candidate must pass the ordinary native-field, primitive-interior, original
surface and Float32-pose checks. A clear candidate never advances the prefix.
Refinement precedes finite-bracket acceptance so a thin obstacle does not
unnecessarily use a later opposite-face contact. No global minimum is claimed.

This combines interval inclusion's explicit tolerance tradeoff with local
positive-witness generation, rather than replacing proof with sparse samples.
Relevant primary sources:
[Wang et al. 2021 inclusion CCD](https://cims.nyu.edu/gcl/papers/2021-CCD.pdf),
[Nielsen/Erleben 2026 spatial-temporal SDF optimization](https://onlinelibrary.wiley.com/doi/10.1111/cgf.70570).
We do not claim to implement either complete paper. The latter's local
optimization can miss contacts; here it cannot produce a no-hit certificate.
A Lipschitz advancement alternative would need a certified whole-primitive
lower field bound and a regional derivative bound across all relevant leaves
and native branch seams; f/L at one sampled point is not sufficient.
[Hart 1996](https://3dvar.com/Hart1996Sphere.pdf),
[Segment Tracing](https://aparis69.github.io/public_html/projects/galin2020_Segment.html).

## Remaining boundaries and preserved diagnosis

Legacy rough_oblique: sphere radius .04 at (2.3,1,-.6), motion (1.2,-2,1.2).
Depth-48 uncertainty begins near t=0.400957161898347, without budget exhaustion.
Static probes found the old contact constructor unresolved through .40135 and
a real surface witness at .4014. That ~1.16mm gap explains why a simple 1mm
early stop did not close this case. It does not prove exact tangency or a
field discontinuity. The improved candidate constructor plus 0.5mm/1mm
brackets closes it, with independent endpoint checks; 0.1mm remains Unknown.

Exact initial touch_inward, touch_away and graze still fail the initial
strict-separation certificate. They return explicit Unknown, not clear and
not a claimed true hit. A finite budget alone cannot guarantee strict sign
separation at exact tangency. They remain reproducible contract cases.
Source-mesh error, plugin SDFs, rotating sweeps and dynamic rigid-body CCD
remain separate capabilities. No source triangle substitute or hidden
precision relaxation is used.
