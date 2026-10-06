#!/usr/bin/env bash
# Runs audit.sh against every fixture from matrix.sh plus a clean repo, and
# checks that auditing never runs the configured program itself.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
work=$(mktemp -d)
export LAB_HOOK=$work/hook.sh LAB_LOG=$work/log
write_hook "$LAB_HOOK"
: > "$LAB_LOG"
fail=0
for key in clean fsmonitor filter-clean filter-smudge textconv diff-external hooksPath hooksDir sshCommand pager; do
  make_repo "$work/$key" "$key"
  "$here/audit.sh" "$work/$key" > /dev/null; rc=$?
  want=1; [ "$key" = clean ] && want=0
  [ $rc -eq $want ] && res=ok || { res=FAIL; fail=1; }
  printf '%-14s exit %s (want %s) %s\n' "$key" "$rc" "$want" "$res"
done
if [ -s "$LAB_LOG" ]; then echo "FAIL: auditing ran a program:"; cat "$LAB_LOG"; fail=1; else echo "auditing ran no programs"; fi
rm -rf "$work"
exit $fail
