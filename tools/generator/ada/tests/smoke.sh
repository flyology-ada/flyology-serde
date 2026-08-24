#!/bin/sh
set -eu

generator_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
generator="$generator_root/bin/flyology_serde_generate"
scaffold_tests="$generator_root/tests/bin/scaffold_tests"
renderer_tests="$generator_root/tests/bin/renderer_tests"
overlay_fixture="$generator_root/../tests/fixtures/wire-record-overlay.json"
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
"$scaffold_tests" "$overlay_fixture"
python3 "$generator_root/../generate.py" --type-ir "$type_ir_fixture" \
  --overlay "$overlay_fixture" --output "$test_root/python" --test-fixture-shape
"$renderer_tests" \
  "$golden_root/flyology-generated.ads" "$golden_root/flyology-generated.adb" \
  "$test_root/python/flyology-generated.ads" "$test_root/python/flyology-generated.adb"
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
