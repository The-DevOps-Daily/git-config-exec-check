#!/usr/bin/env bash
# The terminal session in the write-up: a workspace restored from a tarball (as a
# CI cache would restore it), then git status, a hardened git diff, and the audit.
# Prints each command after "$ " and its output.
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
cd "$work"
cat > hook.sh <<'H'
#!/bin/sh
echo "ran: $1" >> "$(dirname "$0")/ran.log"
case $1 in filter-clean) cat ;; fsmonitor) exit 1 ;; esac
H
chmod +x hook.sh
git init -q -b main workspace
(
  cd workspace
  git config user.email lab@example.com
  git config user.name lab
  printf 'hello\n' > notes.txt
  printf '*.txt filter=lab\n' > .gitattributes
  git add -A && git commit -qm init
  printf 'changed\n' >> notes.txt
  git config core.fsmonitor "../hook.sh fsmonitor"
  git config filter.lab.clean "../hook.sh filter-clean"
)
tar -czf cache.tgz -C workspace .
mkdir restored && tar -xzf cache.tgz -C restored
cd restored
export PATH=$here:$PATH
show() { echo "\$ $1"; bash -c "$1" 2>&1; }
: > ../ran.log
show "git status --short"
show "cat ../ran.log"
: > ../ran.log
show "git diff --no-ext-diff --no-textconv --stat"
show "cat ../ran.log"
show 'audit.sh .; echo "exit $?"'
cd / && rm -rf "$work"
