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
        flyology_serde-deserializers-json-event_readers.adb >/dev/null
      for unit in \
        flyology_serde-json_event_drivers \
        flyology_serde-json_preflights \
        flyology_serde-deserializers-json-event_readers
      do
         object="$repository/tests/obj/json_hook_elision/$mode/$unit.o"
         if ! test -r "$object"; then
            echo "$unit object is missing after $mode $optimization compilation" >&2
            exit 1
         fi
         if nm "$object" | grep -qi flyology_serde_disabled_json_driver; then
            echo "disabled hook sentinel survived in $unit at $mode $optimization" >&2
            exit 1
         fi
         if test "$mode" = enabled; then
            if ! nm "$object" | grep -qi json_event_driver_test_hooks; then
               echo "enabled hook disappeared from $unit at $optimization" >&2
               exit 1
            fi
         elif nm "$object" | grep -qi json_event_driver_test_hooks; then
            echo "disabled hook survived in $unit at $optimization" >&2
            exit 1
         fi
      done
   done
done
