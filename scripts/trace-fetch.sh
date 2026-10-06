#!/usr/bin/env bash
# Why the fetch row shows fsmonitor: trace a fetch in the fsmonitor fixture, which
# has no remote called origin. Shows the programs git started, then the error.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
work=$(mktemp -d)
export LAB_HOOK=$work/hook.sh LAB_LOG=$work/log
write_hook "$LAB_HOOK"
make_repo "$work/r" fsmonitor
cd "$work/r"
echo "git $(git --version | awk '{print $3}') on $(uname -sm)"
GIT_TRACE=1 git fetch origin 2>&1 | grep -E 'run_command|fatal' | sed -E "s#$work#<tmp>#g; s/^[0-9:.]+ +//"
cd / && rm -rf "$work"
