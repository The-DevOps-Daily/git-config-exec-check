# git-config-exec-check

```bash
git clone https://github.com/The-DevOps-Daily/git-config-exec-check
cd git-config-exec-check
scripts/matrix.sh        # which everyday git commands run which repo-supplied programs
scripts/delivery.sh      # which ways of copying a repo also bring its .git/config and hooks
scripts/overrides.sh     # do the usual "safe git" flags stop it
scripts/audit.sh /path/to/repo   # list repo config and hooks that can run programs (exit 0 none, 1 found, 2 error)
```

Plain bash and git. Every "payload" only appends a line to a log file in a temp directory. The ownership step in `delivery.sh` uses `sudo chown` and is skipped without passwordless sudo.

Write-up: [A poisoned .git/config runs code on `git status`](https://devops-daily.com/posts/poisoned-git-config-git-status-runs-code)

## What each script does

- `scripts/lib.sh` builds the test repos: one committed file, one modified file, and a `.git/config` (or `.git/hooks`) that points one setting at a logging script.
- `scripts/matrix.sh` runs 15 everyday commands in a fresh copy of each repo and records the exit code and which programs ran. Output: `results/matrix-git-<version>-<os>.tsv`.
- `scripts/delivery.sh` builds one repo with `core.fsmonitor`, a clean filter and a hook, all calling a helper stored inside `.git`, copies it with `git clone`, a bundle and `tar`, and records what ran during the copy and during `git status` and `git diff` afterwards. It also gives the tar copy to another user to test git's `safe.directory` ownership check.
- `scripts/overrides.sh` starts each row from a fresh copy and runs `git status` and `git diff` with more protection: `--no-ext-diff --no-textconv`, then `-c core.fsmonitor=false -c core.hooksPath=/dev/null`, then the filter driver by name, then `hook.<event>.enabled=false`.
- `scripts/audit.sh` lists repo-level config keys whose value is a command, hooks directory or include, plus executable hooks in the repo's hooks directory. It exits 0 (none), 1 (found) or 2 (could not inspect). It runs only `git rev-parse`, `git --no-pager config` and `find`. It is a detector for the listed settings, not a safety certificate; run a trusted copy kept outside the repo you check. `scripts/audit-selftest.sh` checks it against every fixture plus odd layouts (a driver name containing `=`, shell aliases, a symlinked hook, a linked worktree, an include outside `.git`) and checks that auditing runs nothing.
- `scripts/demo-restored-workspace.sh` is the terminal session in the write-up. `scripts/trace-fetch.sh` traces why a failing `git fetch` still runs fsmonitor.

## Results

Recorded with git 2.39.5 on a Raspberry Pi (Debian 12), and git 2.55.0 on GitHub-hosted `ubuntu-latest` (image ubuntu24 20260927.320.1) and `macos-latest` (macos26 20260907.0351.1) runners ([run 37426875468](https://github.com/The-DevOps-Daily/git-config-exec-check/actions/runs/37426875468)). Files are in `results/`. This is the git 2.55.0 table; Ubuntu and macOS were identical, and git 2.39.5 differed only in the config hook column, because hooks defined in config arrived in git 2.54.

A blank cell means "not observed with this fixture", not "can never run". The fixture appends a line to a committed file, so git can see the change from the file size without filtering it. `hooks dir` is the same for `.git/hooks` and `core.hooksPath`. `process` is a `filter.<name>.process` helper that does not speak the protocol: git 2.39.5 exited 128 after starting it, git 2.55.0 exited 0. Only the `sshCommand` fixture has a remote, and its fetch fails on purpose.

| Command | fsmonitor | clean | process | smudge | textconv | diff.external | hooks dir | config hook | sshCommand |
|---|---|---|---|---|---|---|---|---|---|
| `git status` | runs |  |  |  |  |  | post-index-change | runs |  |
| `git status --porcelain` | runs |  |  |  |  |  | post-index-change | runs |  |
| `git diff` | runs | runs | runs |  | runs | runs |  |  |  |
| `git diff --no-ext-diff --no-textconv` | runs | runs | runs |  |  |  |  |  |  |
| `git log -p -1` |  |  |  |  | runs |  |  |  |  |
| `git log --oneline -1` |  |  |  |  |  |  |  |  |  |
| `git show HEAD` |  |  |  |  | runs |  |  |  |  |
| `git blame notes.txt` | runs | runs | runs |  | runs |  |  |  |  |
| `git ls-files` | runs |  |  |  |  |  |  |  |  |
| `git rev-parse HEAD` |  |  |  |  |  |  |  |  |  |
| `git add -A` | runs | runs | runs |  |  |  | post-index-change | runs |  |
| `git commit -qam wip` | runs | runs | runs |  |  |  | post-commit, post-index-change, pre-commit, reference-transaction | runs |  |
| `git stash` | runs | runs | runs | runs |  |  | post-index-change, reference-transaction | runs |  |
| `git checkout -- notes.txt` | runs |  | runs | runs |  |  | post-checkout, post-index-change | runs |  |
| `git fetch origin (fails)` | runs |  |  |  |  |  |  |  | runs |

`pager` never ran because the commands had no terminal.

`scripts/overrides.sh` on git 2.55.0:

```text
git 2.55.0 on Linux x86_64
plain                                                    exit 0/0  ran: diff-external,filter-clean,fsmonitor,hook:config,hook:dir
diff --no-ext-diff --no-textconv                         exit 0/0  ran: filter-clean,fsmonitor,hook:config,hook:dir
+ -c core.fsmonitor=false -c core.hooksPath=/dev/null    exit 0/0  ran: filter-clean,hook:config
+ -c filter.lab.clean= (needs the driver name)           exit 0/0  ran: hook:config
+ -c hook.post-index-change.enabled=false (per event)    exit 0/0  ran:
```

In this fixture, `core.hooksPath=/dev/null` did not stop a hook defined in config, and adding `hook.post-index-change.enabled=false` (documented in git 2.55) did, without knowing the hook's name. Keep `core.hooksPath=/dev/null` as well: the event switch was only tested together with it.

`scripts/delivery.sh`: `git clone` and a clone from a bundle never brought the config or hooks; a `tar` of the working copy always did. On the GitHub-hosted runners `safe.directory` is already `*` (system config on Ubuntu, global config on macOS), so a copy owned by another user still ran everything; with system and global config switched off, git 2.55 refused it like git 2.39 on the Pi.

## Not covered

Windows, credential helpers, editors, a fetch that succeeds, a process filter that speaks the protocol, and any specific AI coding agent. The scripts test git itself; how an agent calls git decides which rows of the table apply to it.

## License

MIT
