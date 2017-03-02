#!/bin/sh
# /etc/acpi/default.sh
# Default acpi script that takes an entry for all actions

set $*

group=${1%%/*}
action=${1#*/}
device=$2
id=$3
value=$4

handler="/etc/acpi/actions/$group/$action.sh"
if test -x "$handler"
then
    $handler $device $id $value
    exit $?
fi

logger -p $$ "ACPI event unhandled: $* (tried $handler)"
exit 1
