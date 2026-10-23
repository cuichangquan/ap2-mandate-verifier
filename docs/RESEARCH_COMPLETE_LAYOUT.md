# Root research layout completion — current candidate / LIMITED_LOCAL_VALIDATION_PASSED

Basea8befd0b2aa79334cb843efd382a7b32a21de47f. Sixroot inputs/locks and five
research directories now have one research/ home. lib/test/docs/.github and
normal Gemroot files stay. All oldpaths, sizes/contenthash and allowed changed
execution sources are in RESEARCH_COMPLETE_LAYOUT.json. HistoricalJSON/results/
locks/manifests/README records retain exactbytes. Changed executable paths have
newsource identity, not retroactive validation of the oldrun.

Stages:1packaging_candidate22files pure move;2active6+Stage15/security readers;
3Linuxharness/currentmanifest/manualworkflow references. No automatic trigger
is added, no Actions/Gem build/install/acquisition is performed. Prior PR170/171
notes are historical stages, not assertions the remaining files stay in root.

Original fixed logical PINS/LOCKS names+SHA remain. The relocated security
comparison uses explicitly named CURRENT_ADAPTER_SHA; oldsource identity is
retained at the baseGitcommit and oldreports. Existing signature/Schema/claim/
rejection/Evidence predicates are unchanged. Oldreport admission still rejects
when current source/environment identity differs. No arbitrary resolver,
old/new identity fallback, symlink or download mechanism was added.

Linux MANIFEST.json originals are preserved. CURRENT_MANIFEST.json records
relocated current paths/sourcehash separately and is explicitly NOT_RUN.
ManualWorkflow command/hash points to it without execution. Stage15's original runtime contract ap2=0.0.0 predates packagingpre2. Its new
CURRENT manifest declarespre2+Digest from the unchanged currentGemfile.lock,
not a newruntime observation. Standalone oldStage15/security candidate/runtime
records remain historical and are not promoted to current package verification.
Stage18's pre2 capture/harness is also not a newsuccessfulLinuxrun. Captured
current test paths/fixture paths agree with the newlayout. Old successful run
39774818984/39869876461 remain identified by their originalcommit/manifest.

Historical reproduction uses a normal worktree at the originalcommit, restoring
original paths and scripts. No vulnerable historical Ruby parser is run in this
cleanup. OldStage11 seven-source replay vs currentten-source mismatch remains.
Current API/Evidence acceptance, Gem13payload/gemspec/GemSHA remain unchanged.

Required bounded validation is relocation/content/pin/currentmanifest checks,
existing PythonIO/identity/optimization controls and affected Rubytrust/integration
regressions only. Newresults live outside historicalresults. No fullnewOracle,
resource study or dependency install is needed. Merge/release are not approved.

## Local validation (newresults, not historical runs)

Layout79original inventory/path/hash/pins/currentmanifests and previous30moves/
9path references passed. Pythonidentity64,IO10,optimized-invocation4 controls;
Rubytrust147/integration16 cases; sixRuby syntax checks and PythonAST passed.
One initial previous-test expected-prefix failure was repaired within path-only
scope; no rejection predicate or historical pin was relaxed. Initialfailed log
remains preserved. This is not a newLinux run/fullOracle/full885 regression or
freshGem installation. Old7source reportidentity mismatch is unchanged.
Commands used only existingMBA dependencies/saved input; no fetch/CI/build.
