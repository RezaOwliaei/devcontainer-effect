# Strace-instrumented flake hunt for oven-sh/bun#39972

This branch exists only to give the Bun maintainers a `strace`-backed,
repeatable reproduction attempt for
[oven-sh/bun#39972](https://github.com/oven-sh/bun/issues/39972), run
through the actual Dev Container flow (not a standalone `docker build`).
It is not meant to be merged — `main` doesn't have this instrumentation, and
`.devcontainer/Dockerfile` here hard-pins Bun 1.4.0 (the known-bad version)
on purpose.

Context: `Jarred-Sumner` fixed one real bug in
[#40063](https://github.com/oven-sh/bun/pull/40063) (a tarball connection
dying mid-body was reported as `Fail extracting tarball` instead of
`ConnectionClosed`, and never retried), but could not reproduce the
extractor mishandling a *complete* body despite ~1,250 chaos-tested installs
on Linux x64. This branch tests the theory that it's connection-quality
dependent, by deliberately adding network pressure during `bun install` and
capturing a syscall trace if/when it fails.

## What's different from `main`

- `.devcontainer/Dockerfile`: hard-pinned to `oven/bun:1.4.0-debian`, plus
  `strace` added to the apt package list.
- `.devcontainer/devcontainer.json`: `runArgs` gained
  `--cap-add=SYS_PTRACE` and `--security-opt seccomp=unconfined` — required
  for `strace` to work at all inside the container (Docker's default
  seccomp profile blocks `ptrace`).
- `.devcontainer/scaffold.sh`: the vendoring + install tail now loops up to
  20 attempts. Each attempt resets `repos/effect`, `node_modules`, and the
  Bun install cache, then runs a full unsquashed-equivalent `git clone` of
  `Effect-TS/effect` in the background concurrently with a
  `strace`-wrapped `bun install`, so both compete for bandwidth during the
  actual tarball-download window. Stops at the first failure so that
  attempt's logs survive; reports and exits 0 if all 20 pass.

## How to run it

1. Open this repo (on this branch) in VS Code.
2. Run **Dev Containers: Rebuild Container**.
3. Wait — this can take a while. Each attempt races a full Effect repo
   clone against a real `bun install`, up to 20 times. A failed
   `postCreateCommand` shows as an error in the Dev Containers UI but
   doesn't block using the container; it just means an attempt reproduced
   the bug and stopped the loop early.
4. Check `strace-logs/` in the workspace root:
   - `attempt-<n>-<timestamp>.bun-output.log` — `bun install`'s own
     stdout/stderr for that attempt (the actual error text, if any).
   - `attempt-<n>-<timestamp>.strace.log` — the syscall trace for that same
     attempt (`-f -tt -yy`, filtered to network + a few filesystem
     syscalls).

## What to report back on #39972

- Whether it reproduced, and on which attempt (out of 20).
- The exact error text from the matching `bun-output.log`.
- The tail of the matching `strace.log` around the failure — in particular
  whether a `ConnectionClosed`-style event shows up on a socket fd right
  before the failure (supports the #40063 theory), or something else
  (a distinct bug).
