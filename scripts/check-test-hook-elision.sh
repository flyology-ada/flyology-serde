#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project="$repository/tests/json_event_driver_hook_elision.gpr"
for mode in disabled enabled; do
   object="$repository/tests/obj/json_hook_elision/$mode/flyology_serde-json_event_drivers.o"
   for optimization in -O0 -O2; do
      alr -C "$repository" exec -- gprbuild -f -p -u -P "$project" \
        -XHOOK_MODE="$mode" -XHOOK_OPT="$optimization" \
        flyology_serde-json_event_drivers.adb >/dev/null
      if ! test -r "$object"; then
         echo "JSON-driver object is missing after $mode $optimization compilation" >&2
         exit 1
      fi
      if nm "$object" | grep -qi flyology_serde_disabled_json_driver; then
         echo "disabled JSON-driver sentinel survived $mode $optimization compilation" >&2
         exit 1
      fi
      if test "$mode" = enabled; then
         if ! nm "$object" | grep -qi json_event_driver_test_hooks; then
            echo "enabled JSON-driver hook disappeared at $optimization" >&2
            exit 1
         fi
      elif nm "$object" | grep -qi json_event_driver_test_hooks; then
         echo "disabled JSON-driver hook survived $optimization compilation" >&2
         exit 1
      fi
   done
done
