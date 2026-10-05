#!/usr/bin/env bash
# Do the usual "safe git" flags stop a poisoned .git/config? One repo sets
# core.fsmonitor, core.hooksPath, diff.external, a textconv driver and a clean
# filter. Each row runs `git status` and `git diff` with more protection.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
work=$(mktemp -d)
export LAB_HOOK=$work/hook.sh LAB_LOG=$work/log
write_hook "$LAB_HOOK"

make_repo "$work/r" filter-clean
(
  cd "$work/r"
  printf '*.txt filter=lab diff=lab\n' > .gitattributes
  git add .gitattributes && git commit -qm attrs
  printf 'changed again\n' >> notes.txt
  git config core.fsmonitor "$LAB_HOOK fsmonitor"
  git config diff.external "$LAB_HOOK diff-external"
  git config diff.lab.textconv "$LAB_HOOK textconv"
  mkdir -p .lab-hooks
  printf '#!/bin/sh\n"%s" hook:post-index-change\n' "$LAB_HOOK" > .lab-hooks/post-index-change
  chmod +x .lab-hooks/post-index-change
  git config core.hooksPath "$work/r/.lab-hooks"
)

row() { # row <label> <git args...> ; diff flags come from $DIFF_FLAGS
  local label=$1
  shift
  : > "$LAB_LOG"
  (cd "$work/r" && git "$@" status --porcelain >/dev/null 2>&1 && git "$@" diff $DIFF_FLAGS >/dev/null 2>&1)
  printf '%-58s ran: %s\n' "$label" "$(cut -d' ' -f1 "$LAB_LOG" | sort -u | paste -sd, -)"
}

echo "git $(git --version | awk '{print $3}') on $(uname -sm)"
DIFF_FLAGS='' row "plain"
DIFF_FLAGS='--no-ext-diff --no-textconv' row "diff --no-ext-diff --no-textconv"
DIFF_FLAGS='--no-ext-diff --no-textconv' row "+ -c core.fsmonitor=false -c core.hooksPath=/dev/null" \
  -c core.fsmonitor=false -c core.hooksPath=/dev/null
DIFF_FLAGS='--no-ext-diff --no-textconv' row "+ -c filter.lab.clean= (needs the driver name)" \
  -c core.fsmonitor=false -c core.hooksPath=/dev/null -c filter.lab.clean=
rm -rf "$work"
