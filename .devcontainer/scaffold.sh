#!/usr/bin/env bash
# postCreateCommand entry point. Runs once per container creation (and again
# on rebuild) with cwd = workspaceFolder. Every step below is idempotent —
# it only writes/does something if that thing doesn't already exist — so
# re-running this on rebuild never clobbers project work.
set -euo pipefail

templates=".devcontainer/templates"

fresh_project=false
if [ ! -f package.json ]; then
	fresh_project=true
	sed "s/__PROJECT_NAME__/$(basename "$PWD")/" "$templates/package.json" >package.json
fi

[ -f tsconfig.json ] || cp "$templates/tsconfig.json" tsconfig.json
[ -f .oxlintrc.json ] || cp "$templates/.oxlintrc.json" .oxlintrc.json
[ -f .gitignore ] || cp "$templates/.gitignore" .gitignore
[ -f AGENTS.md ] || cp "$templates/AGENTS.md" AGENTS.md

mkdir -p .vscode
[ -f .vscode/settings.json ] || cp "$templates/settings.json" .vscode/settings.json

# Only scaffold an entrypoint for a genuinely new project (package.json was
# also missing) — never add one next to an existing project's own layout
# just because it happens not to have a top-level index.ts.
if [ "$fresh_project" = true ] && [ -z "$(find . -maxdepth 1 -name '*.ts' -not -path './node_modules*' 2>/dev/null)" ]; then
	cp "$templates/index.ts" index.ts
fi

# git subtree needs a repo with at least one commit to attach the vendored
# subtree's merge commit to.
[ -d .git ] || git init -q

# A fresh container has no ~/.gitconfig at all — nothing mounts one in — so
# `git commit` below fails with "unknown author identity" without this.
# HOST_GIT_NAME/HOST_GIT_EMAIL come from devcontainer.json's containerEnv
# (passed through from the host, when set there); fall back to a generic
# identity otherwise so this never blocks the scaffold on a host that hasn't
# set them.
git config user.email >/dev/null 2>&1 || git config user.email "${HOST_GIT_EMAIL:-devcontainer@localhost}"
git config user.name >/dev/null 2>&1 || git config user.name "${HOST_GIT_NAME:-devcontainer}"

if ! git rev-parse HEAD >/dev/null 2>&1; then
	git add -A
	git commit -q -m "chore: scaffold Effect dev container project"
fi

# --- oven-sh/bun#40063 PR-build test (THIS BRANCH ONLY, not for merge to
# main) ---
#
# Jarred-Sumner asked (oven-sh/bun#39972) for the #40063 PR build to be run
# on this exact setup, since he couldn't reproduce the extractor mishandling
# a complete body on Linux x64 despite ~1,250 chaos-tested installs, but
# this OrbStack setup hits the flake ~1/6-1/17. Fetches the PR's CI-built
# binary once (same command he gave: `bunx bun-pr 40063`), then reuses the
# same clean-state -> concurrent-network-pressure -> strace loop from the
# #39972 hunt (see bun-1.4.0-strace-repro, this branch's parent) against
# that binary instead of the stock `bun install`. `--verbose` per his
# request, so a silently-retried `ConnectionClosed` shows up in the log
# instead of being invisible.
#
# Pressure source: a full, un-cached `git clone --no-single-branch` of
# Effect-TS/effect run in the background concurrently with the install, so
# both contend for the same limited bandwidth during the tarball-download
# window. Deliberately a plain `git clone` here, not `git subtree add`: same
# network profile, but it never touches this repo's own .git index/HEAD,
# which matters because this job gets killed between attempts — killing a
# real `git subtree add` mid-merge would risk corrupting this scaffold
# repo's git state across up to 20 iterations.
# By default bun-pr installs next to the resolved `bun` binary
# (/usr/local/bin, root-owned in this image) — fails with "Permission
# denied" as the non-root bun user this container actually runs as.
# BUN_OUT_DIR overrides that; verified locally that bun-pr honors it. Put
# it on PATH too so `bun-40063` resolves bare, same as Jarred's example.
# Also verified locally: the tool needs `unzip` (present in this image)
# and fails outright without it.
export BUN_OUT_DIR="$HOME/.local/bin"
mkdir -p "$BUN_OUT_DIR"
export PATH="$BUN_OUT_DIR:$PATH"
bunx bun-pr 40063

ATTEMPTS=20
LOGDIR="strace-logs"
mkdir -p "$LOGDIR"
BUN_CACHE="$HOME/.bun/install/cache"

for i in $(seq 1 "$ATTEMPTS"); do
	echo "=== attempt $i/$ATTEMPTS ==="
	rm -rf repos/effect node_modules
	# $BUN_CACHE is a mount point (the bun-install-cache named volume) — rm
	# -rf on the directory itself fails with "Device or resource busy"; only
	# its contents can be removed.
	find "$BUN_CACHE" -mindepth 1 -delete

	git clone --no-single-branch -q https://github.com/Effect-TS/effect.git repos/effect &
	pressure_pid=$!

	ts=$(date +%s)
	strace_log="$LOGDIR/pr40063-attempt-$i-$ts.strace.log"
	bun_log="$LOGDIR/pr40063-attempt-$i-$ts.bun-output.log"

	# Same broadened filter as the #39972 hunt: `network` covers
	# connect/send*/recv*/socket lifecycle, to see whether a
	# ConnectionClosed-style event correlates with a failure this time.
	# -yy resolves fds to paths/socket info; -s 256 avoids truncating
	# buffer previews to strace's 32-byte default.
	set +e
	strace -f -tt -yy -s 256 \
		-e trace=network,read,write,close,openat,unlinkat,renameat,renameat2 \
		-o "$strace_log" -- bun-40063 install --verbose >"$bun_log" 2>&1
	bun_status=$?
	set -e

	kill "$pressure_pid" 2>/dev/null || true
	wait "$pressure_pid" 2>/dev/null || true

	if [ "$bun_status" -ne 0 ]; then
		echo "!!! REPRODUCED on attempt $i/$ATTEMPTS !!!"
		echo "syscall trace: $strace_log"
		echo "bun output:    $bun_log"
		exit "$bun_status"
	fi
done

echo "did not reproduce in $ATTEMPTS attempts"
