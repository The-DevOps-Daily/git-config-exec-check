# git-config-exec-check

```bash
git clone https://github.com/The-DevOps-Daily/git-config-exec-check
cd git-config-exec-check
scripts/matrix.sh        # which everyday git commands run which repo-supplied programs
scripts/delivery.sh      # which ways of copying a repo also bring its .git/config and hooks
scripts/overrides.sh     # do the usual "safe git" flags stop it
scripts/audit.sh /path/to/repo   # list repo config and hooks that can run programs; exits 1 if any
```

Plain bash and git. Every "payload" only appends a line to a log file in a temp directory. The ownership step in `delivery.sh` uses `sudo chown` and is skipped without passwordless sudo.

Write-up: [A poisoned .git/config runs code on `git status`](https://devops-daily.com/posts/poisoned-git-config-git-status-runs-code)

## What each script does

- `scripts/lib.sh` builds the test repos: one committed file, one modified file, and a `.git/config` (or `.git/hooks`) that points one setting at a logging script.
- `scripts/matrix.sh` runs 15 everyday commands in a fresh copy of each repo and records which ones ran the configured program. Output: `results/matrix-git-<version>-<os>.tsv`.
- `scripts/delivery.sh` builds one repo with `core.fsmonitor`, a clean filter and a hook, copies it with `git clone`, a bundle and `tar`, then runs `git status` and `git diff` in each copy. It also gives the tar copy to another user to test git's `safe.directory` ownership check.
- `scripts/overrides.sh` runs `git status` and `git diff` with more protection on each row: `--no-ext-diff --no-textconv`, then `-c core.fsmonitor=false -c core.hooksPath=/dev/null`, then an override for the filter driver by name.
- `scripts/audit.sh` lists repo-level config keys whose value is a command, hook directory or include, plus executable files in `.git/hooks`. It reads config files only, so it is safe to run before any other git command. `scripts/audit-selftest.sh` checks it against every fixture and checks that auditing runs nothing.

## Results

Recorded with git 2.39.5 on a Raspberry Pi (Debian 12), and git 2.55.0 on GitHub-hosted `ubuntu-latest` and `macos-latest` runners ([run 37423171962](https://github.com/The-DevOps-Daily/git-config-exec-check/actions/runs/37423171962)). The command matrix was identical on all three. Files are in `results/`.

| Command | fsmonitor | clean | smudge | textconv | diff.external | hooksPath | .git/hooks | sshCommand | pager |
|---|---|---|---|---|---|---|---|---|---|
| `git status` | runs |   |   |   |   | post-index-change | post-index-change |   |   |
| `git status --porcelain` | runs |   |   |   |   | post-index-change | post-index-change |   |   |
| `git diff` | runs | runs |   | runs | runs |   |   |   |   |
| `git diff --no-ext-diff --no-textconv` | runs | runs |   |   |   |   |   |   |   |
| `git log -p -1` |   |   |   | runs |   |   |   |   |   |
| `git log --oneline -1` |   |   |   |   |   |   |   |   |   |
| `git show HEAD` |   |   |   | runs |   |   |   |   |   |
| `git blame notes.txt` | runs | runs |   | runs |   |   |   |   |   |
| `git ls-files` | runs |   |   |   |   |   |   |   |   |
| `git rev-parse HEAD` |   |   |   |   |   |   |   |   |   |
| `git add -A` | runs | runs |   |   |   | post-index-change | post-index-change |   |   |
| `git commit -qam wip` | runs | runs |   |   |   | pre-commit, post-commit, post-index-change, reference-transaction | same |   |   |
| `git stash` | runs | runs | runs |   |   | post-index-change, reference-transaction | same |   |   |
| `git checkout -- notes.txt` | runs |   | runs |   |   | post-checkout, post-index-change | same |   |   |
| `git fetch origin` | runs |   |   |   |   |   |   | runs |   |

`pager` never ran because the commands had no terminal. `git clone` and `git clone` from a bundle never brought the config or hooks; a `tar` of the working copy always did. On the GitHub-hosted runners `safe.directory` is already `*` (`/etc/gitconfig` on Ubuntu, `~/.gitconfig` on macOS), so a copy owned by another user still ran everything; with system and global config switched off, git 2.55 refused it like git 2.39 on the Pi.

## Not covered

Windows, `filter.<driver>.process`, credential helpers, editors, and any specific AI coding agent. The scripts test git itself; how an agent calls git decides which rows of the table apply to it.

## License

MIT
