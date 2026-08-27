#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project="$repository/tests/json_event_driver_hook_elision.gpr"
for mode in disabled enabled; do
   for optimization in -O0 -O2; do
      alr -C "$repository" exec -- gprbuild -f -p -u -P "$project" \
        -XHOOK_MODE="$mode" -XHOOK_OPT="$optimization" \
        flyology_serde-json_event_drivers.adb \
        flyology_serde-json_preflights.adb \
        flyology_serde-deserializers-json.adb \
        flyology_serde-deserializers-json_event_readers.adb \
        flyology_serde-adapters-fixed_arrays.adb \
        fixed_array_hook_elision_probe.adb >/dev/null
      for unit in \
        flyology_serde-json_event_drivers \
        flyology_serde-json_preflights \
        flyology_serde-deserializers-json \
        flyology_serde-deserializers-json_event_readers \
        flyology_serde-adapters-fixed_arrays \
        fixed_array_hook_elision_probe
      do
         object="$repository/tests/obj/json_hook_elision/$mode/$unit.o"
         if ! test -r "$object"; then
            echo "$unit object is missing after $mode $optimization compilation" >&2
            exit 1
         fi
         if nm "$object" |
              grep -Eqi \
                'flyology_serde_disabled_(json_driver|fixed_array_candidate)'; then
            echo "disabled hook sentinel survived in $unit at $mode $optimization" >&2
            exit 1
         fi
         if test "$mode" = enabled; then
            case "$unit" in
               fixed_array_hook_elision_probe)
                  if ! nm "$object" | grep -qi fixed_array_test_hooks; then
                     echo "enabled hook disappeared from $unit at $optimization" >&2
                     exit 1
                  fi
                  ;;
               flyology_serde-adapters-fixed_arrays|flyology_serde-deserializers-json)
                  if nm "$object" |
                       grep -Eqi 'json_event_driver_test_hooks|fixed_array_test_hooks'; then
                     echo "unexpected hook survived in $unit at $mode $optimization" >&2
                     exit 1
                  fi
                  ;;
               *)
                  if ! nm "$object" | grep -qi json_event_driver_test_hooks; then
                     echo "enabled hook disappeared from $unit at $optimization" >&2
                     exit 1
                  fi
                  ;;
            esac
         elif nm "$object" |
              grep -Eqi 'json_event_driver_test_hooks|fixed_array_test_hooks'; then
            echo "unexpected hook survived in $unit at $mode $optimization" >&2
            exit 1
         fi
      done
   done
done

#  Rebuild the production project from a clean object tree so obsolete ALIs
#  cannot make an isolation check pass or fail depending on local history.
FLYOLOGY_SERDE_TEST_HOOKS=enabled
export FLYOLOGY_SERDE_TEST_HOOKS
alr -C "$repository" exec -- gprclean -r -P flyology_serde.gpr \
  -XFLYOLOGY_SERDE_TEST_HOOKS=disabled -XLIBRARY_TYPE=static \
  -XFLYOLOGY_JSON_LIBRARY_TYPE=static \
  -XFLYOLOGY_SERDE_LIBRARY_TYPE=static >/dev/null
alr -C "$repository" exec -- gprbuild -p -P flyology_serde.gpr \
  -XFLYOLOGY_SERDE_TEST_HOOKS=disabled -XLIBRARY_TYPE=static \
  -XFLYOLOGY_JSON_LIBRARY_TYPE=static \
  -XFLYOLOGY_SERDE_LIBRARY_TYPE=static >/dev/null

forbidden=$(
   find "$repository/src" "$repository/obj" "$repository/lib" -type f \
     -exec sh -c '
        for artifact do
           case "$artifact" in
              *json-event_readers*)
                 printf "%s\n" "$artifact"
                 continue
                 ;;
           esac
           if strings "$artifact" 2>/dev/null |
                grep -Eqi \
                  "json_handwritten_oracle|json__event_readers|json\\.event_readers|fixed_array_testing|arm_candidate_failure|candidate_attempts|injected fixed-array"; then
              printf "%s\n" "$artifact"
           fi
        done
     ' sh {} +
)
if test -n "$forbidden"; then
   echo "test-only Serde code survived production build:" >&2
   echo "$forbidden" >&2
   exit 1
fi

stage=$(mktemp -d /tmp/flyology-serde-install-check.XXXXXX)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
alr -C "$repository" exec -- gprinstall -r -p -m --mode=dev \
  --prefix="$stage/install" -P flyology_serde.gpr \
  -XFLYOLOGY_SERDE_TEST_HOOKS=disabled -XLIBRARY_TYPE=static \
  -XFLYOLOGY_JSON_LIBRARY_TYPE=static \
  -XFLYOLOGY_SERDE_LIBRARY_TYPE=static >/dev/null

serde_gprs=$(find "$stage/install/share/gpr" -type f -name flyology_serde.gpr)
if test "$(printf "%s\n" "$serde_gprs" | sed '/^$/d' | wc -l | tr -d ' ')" -ne 1; then
   echo "staged install does not contain exactly one Serde project" >&2
   exit 1
fi
if ! grep -Eq '^with "flyology_json";[[:space:]]*$' "$serde_gprs"; then
   echo "installed Serde project lacks its top-level Flyology JSON import" >&2
   exit 1
fi
if test "$(find "$stage/install/share/gpr" -type f -name flyology_json.gpr | wc -l | tr -d ' ')" -ne 1; then
   echo "staged install does not contain exactly one Flyology JSON project" >&2
   exit 1
fi
if test "$(find "$stage/install" -type f -name libFlyology_Serde.a | wc -l | tr -d ' ')" -ne 1; then
   echo "staged install does not contain exactly one static Serde library" >&2
   exit 1
fi
if test "$(find "$stage/install" -type f -name libFlyology_JSON.a | wc -l | tr -d ' ')" -ne 1; then
   echo "staged install does not contain exactly one static Flyology JSON library" >&2
   exit 1
fi

stage_forbidden=$(
   find "$stage/install" -type f -exec sh -c '
      for artifact do
         case "$artifact" in
            *json-event_readers* | *json_handwritten_oracle*)
               printf "%s\n" "$artifact"
               continue
               ;;
         esac
         if strings "$artifact" 2>/dev/null |
              grep -Eqi \
                "json_handwritten_oracle|json__event_readers|json\\.event_readers|fixed_array_testing|arm_candidate_failure|candidate_attempts|injected fixed-array"; then
            printf "%s\n" "$artifact"
         fi
      done
   ' sh {} +
)
if test -n "$stage_forbidden"; then
   echo "test-only Serde code survived staged install:" >&2
   echo "$stage_forbidden" >&2
   exit 1
fi

mkdir -p "$stage/client/src"
cp "$repository/tests/external_json_oracle_rejection/external_json_oracle_rejection.gpr" \
  "$stage/client/"
cp "$repository/tests/external_json_oracle_rejection/src/public_json_client.adb" \
  "$stage/client/src/"
cp "$repository/tests/external_json_oracle_rejection/src/public_fixed_array_client.adb" \
  "$stage/client/src/"
cp "$repository/tests/external_json_oracle_rejection/src/json_oracle_client.adb" \
  "$stage/client/src/"
cp "$repository/tests/external_json_oracle_rejection/src/fixed_array_testing_client.adb" \
  "$stage/client/src/"
cp "$repository/tests/external_json_oracle_rejection/src/limited_fixed_array_client.adb" \
  "$stage/client/src/"

gprbuild_command=$(alr -C "$repository" exec -- sh -c 'command -v gprbuild')
gcc_command=$(alr -C "$repository" exec -- sh -c 'command -v gcc')
toolchain_path=$(dirname "$gprbuild_command"):$(dirname "$gcc_command"):/usr/bin:/bin
client_project="$stage/client/external_json_oracle_rejection.gpr"
mkdir -p "$stage/home" "$stage/tmp"
(
   cd "$stage/client"
   env -i PATH="$toolchain_path" HOME="$stage/home" TMPDIR="$stage/tmp" \
     LANG=C LC_ALL=C GPR_PROJECT_PATH="$stage/install/share/gpr" \
     LIBRARY_TYPE=static FLYOLOGY_JSON_LIBRARY_TYPE=static \
     FLYOLOGY_SERDE_LIBRARY_TYPE=static \
     "$gprbuild_command" -f -p -P "$client_project" \
     public_json_client.adb >/dev/null
)
client_binary="$stage/bin/public_json_client"
if ! test -x "$client_binary"; then
   echo "installed public client binary was not produced" >&2
   exit 1
fi
env -i PATH=/usr/bin:/bin HOME="$stage/home" TMPDIR="$stage/tmp" \
  LANG=C LC_ALL=C "$client_binary"
(
   cd "$stage/client"
   env -i PATH="$toolchain_path" HOME="$stage/home" TMPDIR="$stage/tmp" \
     LANG=C LC_ALL=C GPR_PROJECT_PATH="$stage/install/share/gpr" \
     LIBRARY_TYPE=static FLYOLOGY_JSON_LIBRARY_TYPE=static \
     FLYOLOGY_SERDE_LIBRARY_TYPE=static \
     "$gprbuild_command" -f -p -P "$client_project" \
     public_fixed_array_client.adb >/dev/null
)
fixed_array_binary="$stage/bin/public_fixed_array_client"
if ! test -x "$fixed_array_binary"; then
   echo "installed fixed-array client binary was not produced" >&2
   exit 1
fi
env -i PATH=/usr/bin:/bin HOME="$stage/home" TMPDIR="$stage/tmp" \
  LANG=C LC_ALL=C "$fixed_array_binary"

if rejection=$(
   cd "$stage/client"
   env -i PATH="$toolchain_path" HOME="$stage/home" TMPDIR="$stage/tmp" \
     LANG=C LC_ALL=C GPR_PROJECT_PATH="$stage/install/share/gpr" \
     LIBRARY_TYPE=static FLYOLOGY_JSON_LIBRARY_TYPE=static \
     FLYOLOGY_SERDE_LIBRARY_TYPE=static \
     "$gprbuild_command" -f -p -P "$client_project" \
     json_oracle_client.adb 2>&1
); then
   echo "external client unexpectedly compiled the test-only JSON oracle" >&2
   exit 1
fi
error_count=$(printf "%s\n" "$rejection" | grep -c ': error:' || true)
case "$rejection" in
   *'error: file "flyology_serde-deserializers-json_handwritten_oracle.ads" not found'*)
      if test "$error_count" -eq 1; then
         :
      else
         echo "external JSON-oracle rejection reported extra errors" >&2
         echo "$rejection" >&2
         exit 1
      fi
      ;;
   *)
      echo "external JSON-oracle rejection failed for an unrelated reason" >&2
      echo "$rejection" >&2
      exit 1
      ;;
esac

if rejection=$(
   cd "$stage/client"
   env -i PATH="$toolchain_path" HOME="$stage/home" TMPDIR="$stage/tmp" \
     LANG=C LC_ALL=C GPR_PROJECT_PATH="$stage/install/share/gpr" \
     LIBRARY_TYPE=static FLYOLOGY_JSON_LIBRARY_TYPE=static \
     FLYOLOGY_SERDE_LIBRARY_TYPE=static \
     "$gprbuild_command" -f -p -P "$client_project" \
     fixed_array_testing_client.adb 2>&1
); then
   echo "external client unexpectedly compiled fixed-array test controls" >&2
   exit 1
fi
error_count=$(printf "%s\n" "$rejection" | grep -c ': error:' || true)
case "$rejection" in
   *'error: file "flyology_serde-fixed_array_testing.ads" not found'*)
      if test "$error_count" -eq 1; then
         :
      else
         echo "external fixed-array-control rejection reported extra errors" >&2
         echo "$rejection" >&2
         exit 1
      fi
      ;;
   *)
      echo "external fixed-array-control rejection failed for an unrelated reason" >&2
      echo "$rejection" >&2
      exit 1
      ;;
esac

if rejection=$(
   cd "$stage/client"
   env -i PATH="$toolchain_path" HOME="$stage/home" TMPDIR="$stage/tmp" \
     LANG=C LC_ALL=C GPR_PROJECT_PATH="$stage/install/share/gpr" \
     LIBRARY_TYPE=static FLYOLOGY_JSON_LIBRARY_TYPE=static \
     FLYOLOGY_SERDE_LIBRARY_TYPE=static \
     "$gprbuild_command" -f -p -P "$client_project" \
     limited_fixed_array_client.adb 2>&1
); then
   echo "external client unexpectedly instantiated Fixed_Arrays with a limited element" >&2
   exit 1
fi
error_count=$(printf "%s\n" "$rejection" | grep -c ': error:' || true)
if test "$error_count" -lt 1 || ! printf "%s\n" "$rejection" | grep -Eqi 'limited type|nonlimited'; then
   echo "limited-element Fixed_Arrays rejection failed for an unrelated reason" >&2
   echo "$rejection" >&2
   exit 1
fi
