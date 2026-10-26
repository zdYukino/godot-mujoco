# Spatial test retention and cleanup

Recoverable history before cleanup: local checkpoint
092a5f9a24cc9ddfea66ed7ea0954c91c4555f7b.
No acceptance logs, screenshots, failed attempts or counterexamples were deleted.

- Nine SceneTree tests share query_test_base.gd for initialization, counters
  and frame waits. All geometry-specific inputs and assertions remain local.
- Removed the old sdf_performance.gd three-repeat wrapper. Timing/resource data
  now accompany finite-precision cases, with A/B/C cold/warm in the same checker.
  Its earlier source is recoverable in the checkpoint and logs remain on GTR.
- Removed asset_pair_matrix's audit exit-success exception; Unknown always
  fails that certified-pair matrix.
- Seeded scalar/affine/joint random probes and depth-convergence checks retain
  their original iterations and predicates under --extended. They are useful
  independent numerical evidence, not inflated native end-to-end counts.
- Default core retains deterministic root/exterior/offset ULP/native branch
  probes, analytic joint-domain counterexample, independent SAT oracle,
  primitive/Area/imported ray/overlap/cast, status failure/reset, lifetime,
  fast thin crossing, physical pit-vs-hull control, saved/reopened editor data.
- Five older sweep/capsule/overlap/motion runners previously launched the exact
  same deterministic positive matrix three times in fresh processes. They now run
  once; all per-case predicates, negative suites and reset/lifetime checks remain.
  Independent RID and CharacterBody tests both remain. Repeated-count-only
  consistency assertions were removed with those duplicate launches.
- Strict old SDF cast/thin precision remains explicitly tested at precision=0,
  refinement=false. New finite-budget tests independently check the complete
  <=0.5/1mm bound, both actual poses, owners/normals, unchanged simulation,
  large-coordinate rejection and observable 0.1mm/initial-touch Unknown.
- Known failure history was not erased: original A/B rough-oblique Unknown
  and current exact-touch Unknown are reproduced by --extended comparison
  and the thin-boundary contract. Unknown is never counted as geometric success.

The usage README links to the capability matrix; implementation detail and
historical measurements stay in development documents. Generated __pycache__
and unrelated .vscode files are excluded from project commits.
