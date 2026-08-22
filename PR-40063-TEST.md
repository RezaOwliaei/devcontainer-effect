# Testing oven-sh/bun PR #40063 against #39972

This branch (`bun-40063-pr-test`, off `bun-1.4.0-strace-repro`) runs the
specific test `Jarred-Sumner` asked for in
[oven-sh/bun#39972](https://github.com/oven-sh/bun/issues/39972#issuecomment-5379004808):
run the [#40063](https://github.com/oven-sh/bun/pull/40063) PR build on this
OrbStack setup (where the flake reproduces ~1/6–1/17 of attempts, unlike his
~1,250 chaos-tested Linux x64 installs) and report which of two outcomes
shows up:

- `warn: ConnectionClosed downloading tarball ... Retrying 1/5` (with
  `--verbose`; silently retried otherwise) → his fix in #40063 is doing its
  job, the VM's network path is dropping the connection mid-body.
- `error: Fail extracting tarball for "X": <libarchive's reason> (at byte N
  of M)` → a real extractor/HTTP data bug, not just an unretried close.

Not meant to be merged — same posture as `bun-1.4.0-strace-repro`.

## What's different from `bun-1.4.0-strace-repro`

Only `.devcontainer/scaffold.sh` changed:

- Fetches the PR build once, before the loop, with the exact command
  Jarred gave: `bunx bun-pr 40063`. This needs `unzip` (present in this
  image, verified locally — the tool fails without it) and installs to
  `/usr/local/bin/bun-<sha>-pr40063`, symlinking `bun-40063` (and
  `bun-latest`) alongside it — already on `PATH`, no `./` or `chmod`
  needed.
- The 20-attempt clean-state → concurrent-network-pressure → strace loop is
  otherwise unchanged, except it runs `bun-40063 install --verbose`
  instead of `bun install` — `--verbose` specifically so a
  silently-retried `ConnectionClosed` shows up in the captured output
  instead of being invisible.
- Log filenames are prefixed `pr40063-attempt-N-...` to keep them apart
  from the earlier stock-1.4.0 attempt logs if both ever end up in the same
  `strace-logs/` directory.

## How to run it

Same as `bun-1.4.0-strace-repro`: open this repo on this branch in VS Code,
run **Dev Containers: Rebuild Container**, wait (up to 20 attempts, each
racing a full Effect repo clone against a real install), then check
`strace-logs/pr40063-attempt-*` for the outcome.

## What to report back on #39972

- Whether it reproduced, and on which attempt.
- Which of Jarred's two predicted outcomes showed up in the matching
  `bun-output.log` — the retried `ConnectionClosed` warning, or the new
  detailed `Fail extracting tarball ...: <reason> (at byte N of M)` error.
- If useful, the matching `strace.log` for correlation, same as before.

## Result — attempt 1 of 20, run on 2026-08-22

Ran through the real Dev Container `postCreateCommand` flow (built from
this branch's actual committed `Dockerfile`/`scaffold.sh` via a clean
`git archive` checkout — not a hand-typed reproduction), as the non-root
`bun` user, with the `SYS_PTRACE`/seccomp `runArgs` from `devcontainer.json`.

`bunx bun-pr 40063` fetched cleanly (`bun-40063` resolved to
`/home/bun/.local/bin/bun-bee9b75c...-pr40063` via the `BUN_OUT_DIR` fix,
already on `PATH`). Attempt 1 hit Jarred's first predicted outcome on the
very first try — no need to exhaust all 20:

```
warn: ConnectionClosed downloading tarball @effect/tsgo-linux-arm64@0.36.5. Retrying 1/5...

warn: ConnectionClosed downloading tarball effect@4.0.0-rc.111. Retrying 1/5...
```

Both retries succeeded; the install still completed cleanly (`33 packages
installed [370.29s]`). Exact match to the format he named. No
`Fail extracting tarball ...` error appeared anywhere in the verbose log.

Notably, the background pressure job (the concurrent unsquashed
`Effect-TS/effect` clone) died with `fatal: early EOF` /
`RPC failed; curl 92 HTTP/2 stream ... CANCEL` during this same attempt —
the same class of connection-drop symptom, on a different protocol
(git smart-HTTP vs. bun's own npm tarball fetch), happening concurrently.

Full logs committed at `strace-logs/pr40063-attempt-1-1787405944.*`
(`bun-output.log` is the verbose install output; `strace.log.gz` is the
gzipped syscall trace, 29MB).
