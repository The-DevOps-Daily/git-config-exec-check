#!/usr/bin/env bash
# Which ways of getting a repo onto a machine also bring its .git/config and hooks?
# One repo sets core.fsmonitor, a clean filter and a post-index-change hook. All
# three call a helper stored inside .git, by relative path, so the payload travels
# with the copy. The repo is copied four ways, then `git status` and `git diff`
# run in each copy. "copy ran" is anything that ran while copying.
# The ownership step needs passwordless sudo; it is skipped without it.
set -u
work=$(mktemp -d)
export LAB_LOG=$work/log

git init -q -b main "$work/src"
(
  cd "$work/src"
  git config user.email lab@example.com
  git config user.name lab
  printf 'hello\n' > notes.txt
  printf '*.txt filter=lab\n' > .gitattributes
  git add -A && git commit -qm init
  printf 'changed\n' >> notes.txt
  cat > .git/lab-hook.sh <<'EOF'
#!/bin/sh
echo "$1" >> "$LAB_LOG"
case $1 in filter-clean) cat ;; fsmonitor) exit 1 ;; esac
exit 0
EOF
  chmod +x .git/lab-hook.sh
  # Filters, fsmonitor and hooks run from the top of the working tree.
  git config core.fsmonitor ".git/lab-hook.sh fsmonitor"
  git config filter.lab.clean ".git/lab-hook.sh filter-clean"
  printf '#!/bin/sh\n.git/lab-hook.sh hook:post-index-change\n' > .git/hooks/post-index-change
  chmod +x .git/hooks/post-index-change
)

ran() { cut -d' ' -f1 "$LAB_LOG" | sort -u | paste -sd, -; }

probe() { # probe <label> <dir> <ran during copy> [git -c args...]
  local label=$1 dir=$2 during=$3
  shift 3
  : > "$LAB_LOG"
  local err err2 s1 s2
  err=$(cd "$dir" && git "$@" status --porcelain 2>&1 >/dev/null)
  s1=$?
  err2=$(cd "$dir" && git "$@" diff 2>&1 >/dev/null)
  s2=$?
  local r
  r=$(ran)
  printf '%-38s copy ran: %-8s then ran: %-46s exit %s/%s %s\n' "$label" "${during:-nothing}" "${r:-nothing}" "$s1" "$s2" \
    "$(printf '%s\n%s' "$err" "$err2" | grep -m1 fatal)"
}

echo "git $(git --version | awk '{print $3}') on $(uname -sm)"
sd=$(git config --show-scope --show-origin --get-all safe.directory 2>/dev/null | tr '\t' ' ' | paste -sd';' -)
echo "safe.directory already set on this machine: ${sd:-no}"
probe "original repo" "$work/src" "-"

: > "$LAB_LOG"; git clone -q "$work/src" "$work/clone" 2>/dev/null; during=$(ran)
probe "git clone" "$work/clone" "$during"

: > "$LAB_LOG"
git -C "$work/src" bundle create -q "$work/repo.bundle" --all 2>/dev/null
git clone -q "$work/repo.bundle" "$work/from-bundle" 2>/dev/null; during=$(ran)
probe "git clone from a bundle" "$work/from-bundle" "$during"

: > "$LAB_LOG"
tar -C "$work/src" -czf "$work/workspace.tgz" .
mkdir "$work/from-tar" && tar -C "$work/from-tar" -xzf "$work/workspace.tgz"; during=$(ran)
probe "tar of the working copy" "$work/from-tar" "$during"

if sudo -n true 2>/dev/null; then
  mkdir "$work/other-owner" && tar -C "$work/other-owner" -xzf "$work/workspace.tgz"
  sudo chown -R nobody "$work/other-owner"
  sudo chmod -R a+rwX "$work/other-owner"
  probe "same tar, owned by another user" "$work/other-owner" "-"
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    probe "  ...with no system or global config" "$work/other-owner" "-"
  probe "  ...with -c safe.directory=*" "$work/other-owner" "-" -c safe.directory='*'
  sudo rm -rf "$work/other-owner"
else
  echo "ownership check skipped (needs passwordless sudo)"
fi
rm -rf "$work"
