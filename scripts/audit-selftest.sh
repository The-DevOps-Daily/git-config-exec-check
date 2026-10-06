#!/usr/bin/env bash
# Runs audit.sh against every fixture from matrix.sh plus extra layouts, and
# checks that auditing never runs the configured program itself.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
work=$(mktemp -d)
export LAB_HOOK=$work/hook.sh LAB_LOG=$work/log
write_hook "$LAB_HOOK"
: > "$LAB_LOG"
fail=0
check() { # check <label> <dir> <wanted exit>
  "$here/audit.sh" "$2" > /dev/null 2>&1
  local rc=$?
  local res=ok
  [ $rc -eq "$3" ] || { res=FAIL; fail=1; }
  printf '%-30s exit %s (want %s) %s\n' "$1" "$rc" "$3" "$res"
}
for key in clean fsmonitor filter-clean filter-smudge filter-process textconv diff-external hooksPath hooksDir configHook sshCommand pager; do
  make_repo "$work/$key" "$key"
  want=1; [ "$key" = clean ] && want=0
  check "$key" "$work/$key" $want
done

make_repo "$work/odd-name" clean && git -C "$work/odd-name" config 'filter.a=b.clean' "$LAB_HOOK filter-clean"
check "driver name with =" "$work/odd-name" 1
make_repo "$work/alias" clean && git -C "$work/alias" config alias.st "!$LAB_HOOK alias"
check "shell alias" "$work/alias" 1
make_repo "$work/plain-alias" clean && git -C "$work/plain-alias" config alias.st status
check "plain alias (no program)" "$work/plain-alias" 0
make_repo "$work/symlink" clean && ln -s "$LAB_HOOK" "$work/symlink/.git/hooks/post-index-change"
check "symlinked hook" "$work/symlink" 1
# Setting up a worktree runs the fixture's own hooks, so keep that out of the log.
cp "$LAB_LOG" "$work/log.keep"
make_repo "$work/main" hooksDir && git -C "$work/main" worktree add -q "$work/linked" -b side 2>/dev/null
cp "$work/log.keep" "$LAB_LOG"
check "linked worktree (.git file)" "$work/linked" 1
make_repo "$work/inc" clean && printf '[core]\n\tfsmonitor = %s fsmonitor\n' "$LAB_HOOK" > "$work/inc-target" &&
  git -C "$work/inc" config include.path "$work/inc-target"
check "include.path outside .git" "$work/inc" 1
mkdir "$work/not-a-repo"
check "not a repo" "$work/not-a-repo" 2
check "missing directory" "$work/missing" 2

if [ -s "$LAB_LOG" ]; then echo "FAIL: auditing ran a program:"; cat "$LAB_LOG"; fail=1; else echo "auditing ran no programs"; fi
rm -rf "$work"
exit $fail
