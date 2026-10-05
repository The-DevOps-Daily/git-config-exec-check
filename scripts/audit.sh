#!/usr/bin/env bash
# audit.sh [repo]: list repo-level git config that can make git run a program.
# Exits 1 if it finds any, so it can gate a CI step or an agent wrapper.
# It only runs `git config`, which reads config files and nothing else.
set -u
repo=${1:-.}

# Keys whose value is a command, a hook directory, or a file to include.
exec_keys='^(core\.(fsmonitor|hookspath|sshcommand|pager|editor|askpass|gitproxy|alternaterefscommand)|diff\.external|(diff|filter|merge)\..+\.(textconv|command|clean|smudge|process|driver)|credential(\..+)?\.helper|sequence\.editor|gpg(\..+)?\.program|include\.path|includeif\..+\.path|remote\..+\.(uploadpack|receivepack|vcs)|uploadpack\.packobjectshook)$'

hits=$(git -C "$repo" config --list --includes --show-scope --show-origin 2>/dev/null |
  awk -F'\t' -v re="$exec_keys" '
    ($1 == "local" || $1 == "worktree") {
      split($3, kv, "=")
      key = tolower(kv[1]); val = substr($3, length(kv[1]) + 2)
      if (key == "core.fsmonitor" && (val == "true" || val == "false")) next  # built-in daemon, not a command
      if (key ~ re) printf "%s\t%s\t%s\n", $2, kv[1], val
    }')

if [ -n "$hits" ]; then
  echo "Repo config in $repo can run programs:"
  echo "$hits" | column -t -s$'\t'
  exit 1
fi
echo "No program-running keys in the repo config of $repo"
