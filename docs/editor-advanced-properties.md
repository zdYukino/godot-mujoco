# Application editor properties and viewport operations

Linux / Godot 4.7.2 .NET / MuJoCo 3.16.0. No engine changes.

Scalar hinge/slide joints expose `limited` (JSON boolean), `range` (radians or
metres), nonnegative `damping` and `frictionloss`. Degree-authored MJCF is converted
back to source units on edit. Ball/free joint properties remain read-only.
Polynomial damping coefficients are displayed and retained; scalar replacement
is rejected when higher coefficients are nonzero.

Body `inertia_mode` accepts JSON strings `"automatic"` and `"manual"`. Automatic
uses geometry inertial inference. Geometry explicit mass takes priority over
its density; editing density explicitly clears that geometry mass override.
Manual body mass/inertia takes priority over all geometry mass/density. Editing
geometry mass/density in this mode is rejected instead of silently ignored.

Editing body mass scales existing principal moments by the mass ratio. Editing
`inertia`, `ipos`, or `iquat` selects manual mode. When mass and inertia are edited
together, explicit principal moments override the scaled moments independent of
field order. Principal moments must be positive and satisfy triangle inequalities;
`iquat` must be nonzero and is normalized. `ipos` is body-local centre of mass;
`iquat` is its principal-axis orientation. Existing full-tensor representation is
converted explicitly to principal moments/orientation, not combined with stale
fullinertia. Automatic mode cannot be combined with manual fields in one action.

Left-click a visible geometry to select the closest actual rendered triangle.
The selected geometry gains an emission highlight. Toolbar operations move by
0.1 m or rotate by 5 degrees along/about the chosen local MJCF axis; Size buttons
change all supported dimensions by a factor of 1.1. Numerical fields provide
arbitrary per-axis values. Both paths submit the same document transactions and
Godot undo history, so physics and preview are rebuilt together.

Sphere size is `[radius,0,0]`; cylinder is `[radius,half_height,0]`; box is three
positive half-extents. Extra sphere/cylinder components are rejected. Viewport
sizing never scales a spherical mesh into an ellipsoid. Frame-attached poses and
fromto-derived geometry remain read-only. Pending text blocks viewport operations
and selection changes until Apply/Discard. Structural operations pause preview.

## Independent GUI acceptance

1. Run the editor suite and open its project in the actual editor; select MuJoCo.
2. Import `fixtures/pendulum.xml`. Set hinge range/damping/friction; Apply twice,
   undo, redo, save, close/reopen, and compare the values. Negative range/damping
   must retain the old compiled model and pending text with an error.
3. Select arm body. Apply manual moments `[0.2,0.3,0.4]`, mass 3, ipos and iquat.
   Reject `[1,0.1,0.1]`; inspect unchanged physics. Select automatic separately,
   then change geometry density and verify body mass is recomputed.
4. Add all three shapes. Pick a visible shape in the viewport. Move/rotate/size,
   check numerical fields, undo/redo each, save/reopen and compare physics/visuals.
   Sphere stays spherical. Selecting while a field is pending must not lose it.
5. Import `fixtures/framed.xml`; pose and fromto size remain read-only. Repeat
   after changing selection, running/pausing preview, and disabling/re-enabling
   the plugin. Unsupported fields must remain visibly read-only.

Automatic coverage extends `tests/editor_plugin/acceptance.gd`, including actual
triangle-ray picking and Godot undo. Cloud automation does not replace dot's GUI
acceptance. Cold-import failures remain separate; never count a cached retry as
fresh success.

Source compiler inertia policy is preserved globally. A source that forces geometry
inertia exposes manual fields as read-only; a source that disables inference
cannot switch to automatic. This avoids changing unrelated bodies implicitly.

Validation: expanded editor suite 142/142, exit 0, no ERROR/leak in fresh-import
and runtime logs; native suite 447/447, exit 0. Earlier automatic-mode failure
is retained in `evidence/editor-advanced/first-failed-results.json`.

Real-renderer editor automation executed the actual Apply/Discard signals and
captured three editor images: 145 assertions and process exit 0. This run preceded
the final compiler-policy read-only metadata; final metadata was retested by the
142-check headless suite. The renderer emitted the same two Vulkan probe ERRORs,
so GUI strict acceptance remains failed despite zero assertion failures. See
`evidence/editor-advanced/editor.png` for the rendered editor, not an acceptance
claim. Dot's independent GUI validation is still required.
