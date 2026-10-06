#!/usr/bin/env bash
# Which ways of getting a repo onto a machine also bring its .git/config?
# Builds one repo with core.fsmonitor and a clean filter set, moves it four
# ways, then runs `git status` and `git diff` in each copy.
# The ownership step needs passwordless sudo; it is skipped without it.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

work=$(mktemp -d)
export LAB_HOOK=$work/hook.sh LAB_LOG=$work/log
write_hook "$LAB_HOOK"

make_repo "$work/src" filter-clean
git -C "$work/src" config core.fsmonitor "$LAB_HOOK fsmonitor"

probe() { # probe <label> <dir> [git -c args...]
  local label=$1 dir=$2
  shift 2
  : > "$LAB_LOG"
  local err
  err=$(cd "$dir" && git "$@" status --porcelain 2>&1 >/dev/null; git "$@" diff 2>&1 >/dev/null)
  local ran
  ran=$(cut -d' ' -f1 "$LAB_LOG" | sort -u | paste -sd, -)
  printf '%-38s ran: %-24s %s\n' "$label" "${ran:-nothing}" "$(echo "$err" | head -1)"
}

echo "git $(git --version | awk '{print $3}') on $(uname -sm)"
sd=$(git config --show-origin --get-all safe.directory 2>/dev/null | tr '\t' ' ' | paste -sd';' -)
echo "safe.directory already set on this machine: ${sd:-no}"
probe "original repo" "$work/src"

git clone -q "$work/src" "$work/clone" 2>/dev/null
probe "git clone" "$work/clone"

git -C "$work/src" bundle create -q "$work/repo.bundle" --all 2>/dev/null
git clone -q "$work/repo.bundle" "$work/from-bundle" 2>/dev/null
probe "git clone from a bundle" "$work/from-bundle"

tar -C "$work/src" -czf "$work/workspace.tgz" .
mkdir "$work/from-tar" && tar -C "$work/from-tar" -xzf "$work/workspace.tgz"
probe "tar of the working copy" "$work/from-tar"

if sudo -n true 2>/dev/null; then
  mkdir "$work/other-owner" && tar -C "$work/other-owner" -xzf "$work/workspace.tgz"
  sudo chown -R nobody "$work/other-owner"
  sudo chmod -R a+rwX "$work/other-owner"
  probe "same tar, owned by another user" "$work/other-owner"
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    probe "  ...with no system or global config" "$work/other-owner"
  probe "  ...with safe.directory=*" "$work/other-owner" -c safe.directory='*'
  sudo rm -rf "$work/other-owner"
else
  echo "ownership check skipped (needs passwordless sudo)"
fi
rm -rf "$work"
