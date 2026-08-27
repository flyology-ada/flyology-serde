#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
experiment_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
serde_root=$(CDPATH= cd -- "$experiment_dir/../.." && pwd)
: "${FLYOLOGY_REFLECTION_ROOT:?set FLYOLOGY_REFLECTION_ROOT to the reviewed Reflection checkout}"
temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT HUP INT TERM

expected_reflection_commit=9d3c9b17c8bb510ddfdf8a286e5a192ff929640b
actual_reflection_commit=$(git -C "$FLYOLOGY_REFLECTION_ROOT" rev-parse HEAD)
if [ "$actual_reflection_commit" != "$expected_reflection_commit" ]
then
  echo "unexpected Reflection checkout: $actual_reflection_commit" >&2
  exit 1
fi
if [ -n "$(git -C "$FLYOLOGY_REFLECTION_ROOT" status --porcelain --untracked-files=all)" ]
then
  echo "Reflection checkout is not clean" >&2
  exit 1
fi

reflection_snapshot="$temporary_dir/reflection"
mkdir "$reflection_snapshot"
git -C "$FLYOLOGY_REFLECTION_ROOT" archive \
  --format=tar --output="$temporary_dir/reflection.tar" \
  "$expected_reflection_commit"
tar -xf "$temporary_dir/reflection.tar" -C "$reflection_snapshot"
export FLYOLOGY_REFLECTION_ROOT="$reflection_snapshot"
export FLYOLOGY_SERDE_REFLECTION_BUILD_ROOT="$temporary_dir/integration"
alr -C "$reflection_snapshot" -n build

if rg -n -i 'flyology[._]reflection|libadalang|type[_-]ir' \
  "$serde_root/src" "$serde_root/alire.toml" "$serde_root/flyology_serde.gpr"
then
  echo "Reflection or extractor dependency entered the root Serde crate" >&2
  exit 1
fi
if rg -n -i 'libadalang|type[_-]ir' "$experiment_dir/src"
then
  echo "extractor dependency entered the Reflection integration" >&2
  exit 1
fi

alr -C "$serde_root" exec -- gprbuild -p \
  -P "$experiment_dir/reflection_serialization_experiment.gpr" \
  -aP"$serde_root" -aP"$FLYOLOGY_REFLECTION_ROOT"
"$FLYOLOGY_SERDE_REFLECTION_BUILD_ROOT/bin/reflection_serialization_tests"

if rg -a -n -i 'flyology[._]reflection|libadalang|type[_-]ir' \
  "$serde_root/obj" "$serde_root/lib"
then
  echo "Reflection or extractor symbol entered the root Serde build closure" >&2
  exit 1
fi
if rg -a -n -i 'libadalang|type[_-]ir' \
  "$FLYOLOGY_SERDE_REFLECTION_BUILD_ROOT/obj" \
  "$FLYOLOGY_SERDE_REFLECTION_BUILD_ROOT/bin"
then
  echo "extractor symbol entered the Reflection integration build closure" >&2
  exit 1
fi
