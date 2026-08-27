#!/bin/sh
set -eu

generator_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
serde_root=$(CDPATH= cd -- "$generator_root/../../.." && pwd)
generator="$generator_root/bin/flyology_serde_generate"
scaffold_tests="$generator_root/tests/bin/scaffold_tests"
renderer_tests="$generator_root/tests/bin/flyology_serde_generator-renderer_tests"
production_shape_renderer_tests="$generator_root/tests/bin/"
production_shape_renderer_tests="${production_shape_renderer_tests}flyology_serde_generator-production_shape_renderer_tests"
build_sha_256_tests="$generator_root/tests/bin/build_sha_256_tests"
build_budgets_tests="$generator_root/tests/bin/build_budgets_tests"
atomic_ledgers_tests="$generator_root/tests/bin/atomic_ledgers_tests"
build_attestations_tests="$generator_root/tests/bin/build_attestations_tests"
build_attestations_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_attestations-abort_test"
source_lists_test="$generator_root/tests/bin/flyology_serde_generator-build_attestations-source_lists-test"
source_lists_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_attestations-source_lists-abort_test"
build_budget_session_test="$generator_root/tests/bin/flyology_serde_generator-build_budgets-session_exhaustion_test"
build_processes_tests="$generator_root/tests/bin/build_processes_tests"
build_process_exception_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-exceptional_release_test"
build_process_spawned_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-spawned_release_test"
build_process_raw_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-raw_pipe_abort_test"
build_process_materialization_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-materialization_abort_test"
build_process_spawn_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-spawn_abort_test"
build_process_gate_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-gate_abort_test"
build_process_pipe_transfer_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-pipe_transfer_abort_test"
build_process_commit_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-commit_abort_test"
build_process_close_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-close_abort_test"
build_process_duplicate_transfer_abort_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-duplicate_transfer_abort_test"
build_process_spawn_cleanup_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-spawn_cleanup_test"
build_process_failed_spawn_cleanup_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-failed_spawn_cleanup_test"
build_process_post_primary_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-post_primary_test"
build_process_setup_failure_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-setup_failure_test"
build_process_close_failure_test="$generator_root/tests/bin/flyology_serde_generator-build_processes-close_failure_test"
build_process_abi_tests="$generator_root/tests/bin/build_process_abi_tests"
build_process_signal_child="$generator_root/tests/bin/build_process_signal_child"
hook_elision_project="$generator_root/tests/build_process_hook_elision.gpr"
hook_elision_object="$generator_root/tests/obj/hook_elision/flyology_serde_generator-build_processes.o"
attestation_hook_project="$generator_root/tests/build_attestation_hook_elision.gpr"
attestation_hook_object="$generator_root/tests/obj/attestation_hook_elision/flyology_serde_generator-build_attestations.o"
source_list_hook_object="$generator_root/tests/obj/attestation_hook_elision/"
source_list_hook_object="${source_list_hook_object}flyology_serde_generator-build_attestations-source_lists.o"
source_list_hook_ali="$generator_root/tests/obj/attestation_hook_elision/"
source_list_hook_ali="${source_list_hook_ali}flyology_serde_generator-build_attestations-source_lists.ali"
overlay_fixture="$generator_root/../tests/fixtures/wire-record-overlay.json"
policy_overlay_fixture="$generator_root/../tests/fixtures/wire-record-overlay-policy.json"
type_ir_fixture="$generator_root/../vendor/type_ir/fixtures/wire-record-shape.json"
golden_root="$generator_root/../tests/golden"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM
limits=4096,1048576,2097152,4096,32,8,64,4096,100000,10000,1048576,2097152,3,64,256,4194304

for query_spec in \
  "$generator_root/src/flyology_serde_generator-requests.ads" \
  "$generator_root/src/flyology_serde_generator-overlays.ads"
do
   if awk \
     'BEGIN { RS = ";"; found = 0 } /function/ && /return[[:space:]]+String/ { found = 1 } END { exit !found }' \
     "$query_spec"
   then
      echo "allocating String getter remains in a production query API: $query_spec" >&2
      exit 1
   fi
done

test "$("$generator" --version)" = "serde-generator-v2"
if find "$generator_root/obj" -type f \
  \( -name '*test_fixtures*' -o -name '*production_shape*' \) -print | grep -q .; then
   echo "test-only production-shape code escaped into the production generator build" >&2
   exit 1
fi
if nm "$generator" | grep -Eqi 'test_fixtures|production_shapes'; then
   echo "test-only production-shape symbol escaped into the production generator binary" >&2
   exit 1
fi
"$build_sha_256_tests"
"$build_budgets_tests"
"$atomic_ledgers_tests"
"$build_attestations_tests"
"$build_attestations_abort_test"
"$source_lists_test" "$generator_root/provenance-files-v2.txt"
"$source_lists_abort_test"
"$build_budget_session_test"
"$build_processes_tests"
"$build_process_exception_test"
"$build_process_spawned_test"
"$build_process_raw_abort_test"
"$build_process_materialization_abort_test"
"$build_process_spawn_abort_test"
"$build_process_gate_abort_test"
"$build_process_pipe_transfer_abort_test"
"$build_process_commit_abort_test"
"$build_process_close_abort_test"
"$build_process_duplicate_transfer_abort_test"
"$build_process_spawn_cleanup_test"
"$build_process_failed_spawn_cleanup_test"
"$build_process_post_primary_test"
"$build_process_setup_failure_test"
"$build_process_close_failure_test"
"$build_process_abi_tests" "$build_process_signal_child"
if alr -C "$generator_root" exec -- gprbuild -f -p -u -P \
  "$generator_root/tests/atomic_ledgers_visibility.gpr" atomic_ledgers_visibility_probe.adb \
  >"$test_root/atomic-ledgers-visibility.stdout" \
  2>"$test_root/atomic-ledgers-visibility.stderr"
then
   echo "non-descendant unit unexpectedly imported the private atomic-ledger child" >&2
   exit 1
fi
if ! grep -Eqi 'private child|private unit' "$test_root/atomic-ledgers-visibility.stderr"; then
   echo "atomic-ledger visibility probe failed for an unrelated reason" >&2
   cat "$test_root/atomic-ledgers-visibility.stderr" >&2
   exit 1
fi
for hook_optimization in -O0 -O2; do
   alr -C "$generator_root" exec -- gprbuild -f -p -u -P "$hook_elision_project" \
     -XHOOK_OPT="$hook_optimization" \
     flyology_serde_generator-build_processes.adb >/dev/null
   if nm "$hook_elision_object" | grep -qi flyology_serde_disabled_process; then
      echo "disabled build-process test hook survived $hook_optimization compilation" >&2
      exit 1
   fi
done
for hook_optimization in -O0 -O2; do
   alr -C "$generator_root" exec -- gprbuild -f -p -u -P "$attestation_hook_project" \
     -XHOOK_OPT="$hook_optimization" \
     flyology_serde_generator-build_attestations.adb >/dev/null
   if nm "$attestation_hook_object" | grep -qi flyology_serde_disabled_attestation; then
      echo "disabled build-attestation test hook survived $hook_optimization compilation" >&2
      exit 1
   fi
done
for hook_optimization in -O0 -O2; do
   alr -C "$generator_root" exec -- gprbuild -f -p -u -P "$attestation_hook_project" \
     -XHOOK_OPT="$hook_optimization" \
     flyology_serde_generator-build_attestations-source_lists.adb >/dev/null
   if ! test -f "$source_list_hook_object" || ! test -r "$source_list_hook_object"; then
      echo "source-list hook object is missing after $hook_optimization compilation" >&2
      exit 1
   fi
   if ! test -f "$source_list_hook_ali" || ! test -r "$source_list_hook_ali"; then
      echo "source-list ALI is missing after $hook_optimization compilation" >&2
      exit 1
   fi
   if nm "$source_list_hook_object" | grep -qi flyology_serde_disabled_attestation; then
      echo "disabled source-list test hook survived $hook_optimization compilation" >&2
      exit 1
   fi
   if nm "$source_list_hook_object" | grep -Eqi 'json|sha2|type_ir|libadalang'; then
      echo "source-list parser gained a forbidden dependency under $hook_optimization" >&2
      exit 1
   fi
   if ! awk '
     $1 == "W" && $2 !~ /^(ada|ada[.]finalization|ada[.]unchecked_deallocation|interfaces|system|system[.]soft_links|flyology_serde_generator|flyology_serde_generator[.]build_attestation_test_hooks|flyology_serde_generator[.]build_attestations)%s$/ { bad = 1 }
     END { exit bad }
   ' "$source_list_hook_ali"
   then
      echo "source-list parser gained a non-allowlisted direct unit under $hook_optimization" >&2
      exit 1
   fi
done
"$scaffold_tests" "$overlay_fixture"
python3 "$generator_root/../generate.py" --type-ir "$type_ir_fixture" \
  --overlay "$overlay_fixture" --output "$test_root/python" --test-fixture-shape
"$renderer_tests" \
  "$golden_root/flyology-generated.ads" "$golden_root/flyology-generated.adb" \
  "$test_root/python/flyology-generated.ads" "$test_root/python/flyology-generated.adb" \
  "$overlay_fixture" "$policy_overlay_fixture"
mkdir "$test_root/production-generated"
"$production_shape_renderer_tests" "$test_root/production-generated"
GENERATED_DIR="$test_root/production-generated" \
  alr -C "$serde_root" exec -- gprbuild -f -p -P \
  "$generator_root/tests/production_shape_fixture/production_shape_fixture.gpr"
"$generator_root/tests/production_shape_fixture/bin/production_shape_generated_tests"
generated_ali="$generator_root/tests/production_shape_fixture/obj/production_shapes_serde.ali"
generated_object="$generator_root/tests/production_shape_fixture/obj/production_shapes_serde.o"
if grep -Eqi \
  'type_ir|libadalang|flyology_wire|flyology_json|json_event|flyology_serde_generator|serde_generator' \
  "$test_root/production-generated/production_shapes_serde.ads" \
  "$test_root/production-generated/production_shapes_serde.adb" \
  "$generated_ali"; then
   echo "generated format-neutral adapter gained a forbidden authority/backend dependency" >&2
   exit 1
fi
if strings "$generated_object" | grep -Eqi \
  'type_ir|libadalang|flyology_wire|flyology_json|json_event|flyology_serde_generator|serde_generator'; then
   echo "generated adapter object gained a forbidden authority/backend dependency" >&2
   exit 1
fi
"$generator" --help >/dev/null

if "$generator" >"$test_root/stdout" 2>"$test_root/stderr"; then
   echo "empty command unexpectedly succeeded" >&2
   exit 1
fi
grep -q '^generator/invalid-arguments:' "$test_root/stderr"

if "$generator" --type-ir >"$test_root/stdout" 2>"$test_root/stderr"; then
   echo "missing option value unexpectedly succeeded" >&2
   exit 1
fi
grep -q '^generator/invalid-arguments:' "$test_root/stderr"

if "$generator" --unknown >"$test_root/stdout" 2>"$test_root/stderr"; then
   echo "unknown argument unexpectedly succeeded" >&2
   exit 1
fi
grep -q '^generator/invalid-arguments:' "$test_root/stderr"

if "$generator" --type-ir fixture.json --overlay "$overlay_fixture" --output "$test_root/output" \
  >"$test_root/stdout" 2>"$test_root/stderr"
then
   echo "persisted generation without the fixture gate unexpectedly succeeded" >&2
   exit 1
fi
grep -q '^generator/invalid-arguments:' "$test_root/stderr"
test ! -e "$test_root/output"

if "$generator" --type-ir fixture.json --overlay "$overlay_fixture" --output "$test_root/output" \
  --limits "$limits" --test-fixture-shape >"$test_root/stdout" 2>"$test_root/stderr"
then
   echo "generation unexpectedly succeeded without the reviewed Type IR Ada API" >&2
   exit 1
fi
grep -q '^generator/type-ir-ada-api-unavailable:' "$test_root/stderr"
test ! -e "$test_root/output"

ln -s "$overlay_fixture" "$test_root/overlay-link.json"
if "$generator" --type-ir fixture.json --overlay "$test_root/overlay-link.json" \
  --output "$test_root/output" --limits "$limits" --test-fixture-shape \
  >"$test_root/stdout" 2>"$test_root/stderr"
then
   echo "final overlay symlink unexpectedly accepted" >&2
   exit 1
fi
grep -q '^generator/input-io-error:' "$test_root/stderr"
test ! -e "$test_root/output"

mkfifo "$test_root/overlay-fifo.json"
if "$generator" --type-ir fixture.json --overlay "$test_root/overlay-fifo.json" \
  --output "$test_root/output" --limits "$limits" --test-fixture-shape \
  >"$test_root/stdout" 2>"$test_root/stderr"
then
   echo "overlay FIFO unexpectedly accepted" >&2
   exit 1
fi
grep -q '^generator/input-io-error:' "$test_root/stderr"
test ! -e "$test_root/output"

if "$generator" --type-ir fixture.json --overlay "$test_root" \
  --output "$test_root/output" --limits "$limits" --test-fixture-shape \
  >"$test_root/stdout" 2>"$test_root/stderr"
then
   echo "overlay directory unexpectedly accepted" >&2
   exit 1
fi
grep -q '^generator/input-io-error:' "$test_root/stderr"
test ! -e "$test_root/output"

if "$generator" --type-ir fixture.json --overlay "$overlay_fixture" \
  --output "$test_root/output" --limits 1,2,3 --test-fixture-shape \
  >"$test_root/stdout" 2>"$test_root/stderr"
then
   echo "short limit tuple unexpectedly accepted" >&2
   exit 1
fi
grep -q '^generator/invalid-arguments:' "$test_root/stderr"

if "$generator" --type-ir first --type-ir second --overlay overlay --output output \
  --test-fixture-shape >"$test_root/stdout" 2>"$test_root/stderr"
then
   echo "duplicate singleton option unexpectedly succeeded" >&2
   exit 1
fi
grep -q '^generator/invalid-arguments:' "$test_root/stderr"
