#!/usr/bin/env bash
# For each config key that can run a program, run everyday git commands in a
# fresh copy of a repo whose .git/config sets that key, and record which
# commands ran it. Output: results/matrix-git-<version>-<os>.tsv
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

version=$(git --version | awk '{print $3}')
os=$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)
out=${1:-$here/../results/matrix-git-$version-$os.tsv}
mkdir -p "$(dirname "$out")"
work=$(mktemp -d)
export LAB_HOOK=$work/hook.sh LAB_LOG=$work/log
write_hook "$LAB_HOOK"

keys=(fsmonitor filter-clean filter-smudge filter-process textconv diff-external hooksPath hooksDir configHook sshCommand pager)
cmds=(
  "git status"
  "git status --porcelain"
  "git diff"
  "git diff --no-ext-diff --no-textconv"
  "git log -p -1"
  "git log --oneline -1"
  "git show HEAD"
  "git blame notes.txt"
  "git ls-files"
  "git rev-parse HEAD"
  "git add -A"
  "git commit -qam wip"
  "git stash"
  "git checkout -- notes.txt"
  "git fetch origin"
)

# Columns: key, command, the git exit code, and which programs ran (blank cells
# in the write-up mean "not observed with this fixture", not "can never run").
printf 'key\tcommand\texit\tran\n' > "$out"
for key in "${keys[@]}"; do
  make_repo "$work/template-$key" "$key"
  for cmd in "${cmds[@]}"; do
    rm -rf "$work/run" && cp -a "$work/template-$key" "$work/run"
    : > "$LAB_LOG"
    # hooksPath points at the template; repoint it at this copy.
    [ "$key" = hooksPath ] && git -C "$work/run" config core.hooksPath "$work/run/.lab-hooks"
    (cd "$work/run" && LAB_CMD="$cmd" bash -c "$cmd" > /dev/null 2>&1 < /dev/null)
    rc=$?
    ran=$(cut -d' ' -f1 "$LAB_LOG" | sort -u | paste -sd, -)
    printf '%s\t%s\t%s\t%s\n' "$key" "$cmd" "$rc" "${ran:-no}" >> "$out"
  done
done
rm -rf "$work"
echo "git $version on $os -> $out"
