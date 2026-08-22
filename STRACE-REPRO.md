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

## Results — run on 2026-08-22

**Test conditions:** same host/platform as the original issue report — Linux
aarch64, Debian 13 (trixie) container, run via Docker on OrbStack (macOS
host), `bun install v1.4.0 (34cbb9a40)`, same `devDependencies`/`dependencies`
set as the original repro (`effect`, `@effect/experimental`,
`@effect/language-service`, `@effect/tsgo`, `oxlint`, `oxlint-tsgolint`,
`oxfmt`, `typescript`, `@types/bun`). Run through the real Dev Container
`postCreateCommand` flow (not a standalone `docker run`), with the
concurrent-pressure + strace loop described above, `ATTEMPTS=20`.

**Outcome:** reproduced on **attempt 9 of 20**. Attempts 1–8 all installed
cleanly (33 packages, 131–225s each). Attempt 9:

```
bun install v1.4.0 (34cbb9a40)
error: Fail extracting tarball for "@effect/tsgo-linux-arm64"
error: Fail extracting tarball from @effect/tsgo-linux-arm64
```

**What the syscall trace shows** (full trace attached, gzipped;
`strace -f -tt -yy -s 256 -e trace=network,read,write,close,openat,unlinkat,renameat,renameat2`):

The failing package's extraction singles out one specific file inside its
temp dir (`.tmp/.560acff143397a37-1D.tsgo-linux-arm64`):

- `12:54:33.179` — worker thread 4624 opens
  `artifacts/typescript/7.0.2/tsc` for writing
  (`O_WRONLY|O_CREAT|O_TRUNC`), creating an empty (0-byte) file, fd 41.
- No `write()` call ever lands on that fd — confirmed by grepping the whole
  trace for it.
- Thread 4624 immediately moves on and successfully finishes writing a
  *different* package (`@effect/language-service`), starts on `oxlint`,
  then goes completely silent for **~2m26s** (12:54:35.639 →
  12:57:02.215), after which it resumes — but on yet another package
  (`effect`), never returning to the abandoned `tsc` file.
- The process as a whole is not stalled during that gap: other threads are
  actively receiving data on other TCP connections (Cloudflare-fronted
  registry IPs) throughout, ~38k trace lines in that window.
- At `12:57:36.481`, a *different* thread (4625) closes the orphaned fd and
  recursively removes the whole temp dir (the written `LICENSE`, the
  empty `tsc` file, then the now-empty directories), and `bun` reports the
  extraction failure a few hundred microseconds later.
- No `ConnectionClosed`-style message appears anywhere in `bun`'s own
  output (expected — this is stock 1.4.0, predating #40063's improved
  messaging).

Full logs for this attempt (bun-output + gzipped strace trace) are
committed on this branch under `strace-logs/attempt-9-1787403256.*`, along
with the (uneventful) `bun-output.log` for the 8 successful attempts before
it, for reference.
