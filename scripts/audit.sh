#!/usr/bin/env bash
# audit.sh [repo]: list repo-level git config and hooks that can make git run a program.
# Exit 0: none found. Exit 1: found some. Exit 2: the repo could not be inspected.
# It detects the settings listed below; it is not a safety certificate. Run a copy
# you trust, kept outside the repo you are checking.
# It only runs `git rev-parse`, `git --no-pager config` and `find`, which do not
# run hooks, filters or fsmonitor.
set -u
repo=${1:-.}
fail() { echo "audit: $*" >&2; exit 2; }
[ -d "$repo" ] || fail "no such directory: $repo"

# Finding the repo also applies git's safe.directory ownership check.
common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>&1) ||
  fail "not a git repository, or git refused it: $common"

# Lowercased keys whose value is a command, a hooks directory, or a file to include.
exec_keys='^(core\.(fsmonitor|hookspath|sshcommand|pager|editor|askpass|gitproxy|alternaterefscommand)|diff\.external|(diff|filter|merge)\..+\.(textconv|command|clean|smudge|process|driver)|credential(\..+)?\.helper|sequence\.editor|gpg(\..+)?\.program|include\.path|includeif\..+\.path|remote\..+\.(uploadpack|receivepack|vcs)|uploadpack\.packobjectshook|hook\..*\.command|pager\..+|interactive\.difffilter|trailer\..+\.(cmd|command)|alias\..+)$'

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
git -C "$repo" --no-pager config --list --includes --null --show-scope --show-origin > "$tmp" 2>/dev/null ||
  fail "could not read the config of $repo"

hits=""
# Each entry is scope NUL origin NUL key LF value NUL; a key never contains LF.
while IFS= read -r -d '' scope && IFS= read -r -d '' origin && IFS= read -r -d '' kv; do
  [ "$scope" = local ] || [ "$scope" = worktree ] || continue
  key=${kv%%$'\n'*}
  if [ "$key" = "$kv" ]; then val=""; else val=${kv#*$'\n'}; fi
  lkey=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
  [[ $lkey =~ $exec_keys ]] || continue
  case $lkey in
    core.fsmonitor) if [ "$val" = true ] || [ "$val" = false ]; then continue; fi ;; # built-in daemon
    pager.*) case $val in true | false | yes | no | on | off | 1 | 0 | "") continue ;; esac ;;
    alias.*) if [ "${val#!}" = "$val" ]; then continue; fi ;; # only shell aliases run programs
  esac
  hits+="$origin"$'\t'"$key"$'\t'"$val"$'\n'
done < "$tmp"

# Hooks need no config at all: any executable file (or symlink to one) in the hooks directory runs.
hooks=""
if [ -e "$common/hooks" ]; then
  # -H follows the hooks directory itself if it is a symlink.
  find -H "$common/hooks" -mindepth 1 -maxdepth 1 ! -name '*.sample' -print0 > "$tmp" 2>/dev/null ||
    fail "could not list $common/hooks"
  while IFS= read -r -d '' f; do
    if [ -x "$f" ] && [ ! -d "$f" ]; then hooks+="$f"$'\n'; fi
  done < "$tmp"
fi

if [ -n "$hits" ] || [ -n "$hooks" ]; then
  if [ -n "$hits" ]; then
    echo "Repo config in $repo can run programs:"
    printf '%s' "$hits" | column -t -s $'\t'
  fi
  if [ -n "$hooks" ]; then
    echo "Executable hooks in $common/hooks:"
    printf '%s' "$hooks" | sed 's/^/  /'
  fi
  exit 1
fi
echo "No program-running keys or hooks in the repo config of $repo"
