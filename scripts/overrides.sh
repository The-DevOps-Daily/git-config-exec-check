#!/usr/bin/env bash
# Do the usual "safe git" flags stop a poisoned .git/config? The fixture sets
# core.fsmonitor, a hook in .git/hooks, a hook defined in config (git 2.54+),
# diff.external, a textconv driver and a clean filter. Each row starts from a
# fresh copy, runs `git status` and `git diff`, and adds more protection.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
work=$(mktemp -d)
export LAB_HOOK=$work/hook.sh LAB_LOG=$work/log
write_hook "$LAB_HOOK"

make_repo "$work/template" filter-clean
(
  cd "$work/template"
  printf '*.txt filter=lab diff=lab\n' > .gitattributes
  git add .gitattributes && git commit -qm attrs
  printf 'changed again\n' >> notes.txt
  git config core.fsmonitor "$LAB_HOOK fsmonitor"
  git config diff.external "$LAB_HOOK diff-external"
  git config diff.lab.textconv "$LAB_HOOK textconv"
  printf '#!/bin/sh\n"%s" hook:dir\n' "$LAB_HOOK" > .git/hooks/post-index-change
  chmod +x .git/hooks/post-index-change
  git config hook.lab.event post-index-change
  git config hook.lab.command "$LAB_HOOK hook:config"
)

row() { # row <label> <diff flags> <git args...>
  local label=$1 flags=$2
  shift 2
  rm -rf "$work/r" && cp -a "$work/template" "$work/r"
  : > "$LAB_LOG"
  (cd "$work/r" && git "$@" status --porcelain >/dev/null 2>&1)
  local s1=$?
  (cd "$work/r" && git "$@" diff $flags >/dev/null 2>&1)
  local s2=$?
  printf '%-56s exit %s/%s  ran: %s\n' "$label" "$s1" "$s2" "$(cut -d' ' -f1 "$LAB_LOG" | sort -u | paste -sd, -)"
}

echo "git $(git --version | awk '{print $3}') on $(uname -sm)"
row "plain" ""
row "diff --no-ext-diff --no-textconv" "--no-ext-diff --no-textconv"
row "+ -c core.fsmonitor=false -c core.hooksPath=/dev/null" "--no-ext-diff --no-textconv" \
  -c core.fsmonitor=false -c core.hooksPath=/dev/null
row "+ -c filter.lab.clean= (needs the driver name)" "--no-ext-diff --no-textconv" \
  -c core.fsmonitor=false -c core.hooksPath=/dev/null -c filter.lab.clean=
row "+ -c hook.post-index-change.enabled=false (per event)" "--no-ext-diff --no-textconv" \
  -c core.fsmonitor=false -c core.hooksPath=/dev/null -c filter.lab.clean= -c hook.post-index-change.enabled=false
rm -rf "$work"
