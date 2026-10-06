# Shared helpers. Every "payload" in this repo only appends a line to a log file.

# hook.sh <label>: record that git ran us, then behave enough like the real
# program (filter, textconv, fsmonitor, ssh) for git to carry on.
write_hook() {
  local path=$1
  cat > "$path" <<'EOF'
#!/bin/sh
label=$1
shift
echo "$label ${LAB_CMD:-?}" >> "$LAB_LOG"
case $label in
  filter-clean|filter-smudge) cat ;;          # filters pass content through stdin to stdout
  textconv) cat "$1" ;;                       # textconv gets the file path
  fsmonitor) exit 1 ;;                        # non-zero tells git to fall back to a full scan
  ssh) exit 1 ;;                              # pretend the connection failed
esac
exit 0
EOF
  chmod +x "$path"
}

# make_repo <dir> <key>: a small repo with one committed file, one modified
# file, and a .git/config that sets <key> to run hook.sh.
make_repo() {
  local dir=$1 key=$2
  rm -rf "$dir"
  mkdir -p "$dir"
  (
    cd "$dir"
    git init -q -b main
    git config user.email lab@example.com
    git config user.name lab
    printf 'hello\n' > notes.txt
    case $key in
      filter-clean|filter-smudge) printf '*.txt filter=lab\n' > .gitattributes ;;
      textconv) printf '*.txt diff=lab\n' > .gitattributes ;;
    esac
    git add -A
    git commit -qm init
    printf 'changed\n' >> notes.txt
    case $key in
      fsmonitor) git config core.fsmonitor "$LAB_HOOK fsmonitor" ;;
      filter-clean) git config filter.lab.clean "$LAB_HOOK filter-clean" ;;
      filter-smudge) git config filter.lab.smudge "$LAB_HOOK filter-smudge" ;;
      textconv) git config diff.lab.textconv "$LAB_HOOK textconv" ;;
      diff-external) git config diff.external "$LAB_HOOK diff-external" ;;
      hooksPath)
        mkdir -p .lab-hooks
        for h in pre-commit post-commit post-checkout reference-transaction post-index-change; do
          printf '#!/bin/sh\n"%s" hook:%s\n' "$LAB_HOOK" "$h" > ".lab-hooks/$h"
          chmod +x ".lab-hooks/$h"
        done
        git config core.hooksPath "$dir/.lab-hooks"
        ;;
      hooksDir)
        # No config key at all: hooks placed straight in .git/hooks.
        for h in pre-commit post-commit post-checkout reference-transaction post-index-change; do
          printf '#!/bin/sh\n"%s" hook:%s\n' "$LAB_HOOK" "$h" > ".git/hooks/$h"
          chmod +x ".git/hooks/$h"
        done
        ;;
      sshCommand)
        git config core.sshCommand "$LAB_HOOK ssh"
        git remote add origin ssh://git@example.invalid/lab.git
        ;;
      pager) git config core.pager "$LAB_HOOK pager" ;;
    esac
  )
}
