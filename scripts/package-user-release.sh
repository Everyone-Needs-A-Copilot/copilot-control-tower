#!/bin/bash
# Intentionally inert compatibility tombstone.
#
# Bash executes caller-selected BASH_ENV before reading this file; therefore no
# release logic, credential access, helper invocation, or authority check may
# live at a directly Bash-readable entry point. The supported Swift launcher
# streams the reviewed program resource over private stdin instead.

echo "error: package-user-release.sh contains no release logic; use scripts/package-user-release" >&2
exit 1
