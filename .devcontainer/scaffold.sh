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

# --- oven-sh/bun#39972 repro instrumentation (THIS BRANCH ONLY, not for
# merge to main) ---
#
# Loops clean-state -> concurrent-network-pressure -> strace'd `bun install`
# up to $ATTEMPTS times, stopping at the first failure so its logs survive.
# Pressure source: a full, un-cached `git clone --no-single-branch` of
# Effect-TS/effect run in the background concurrently with `bun install`, so
# both contend for the same limited bandwidth during the tarball-download
# window — simulating the poor-connection conditions suspected of triggering
# #39972. Deliberately a plain `git clone` here, not `git subtree add`: same
# network profile, but it never touches this repo's own .git index/HEAD,
# which matters because this job gets killed between attempts — killing a
# real `git subtree add` mid-merge would risk corrupting this scaffold
# repo's git state across up to 20 iterations.
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
	strace_log="$LOGDIR/attempt-$i-$ts.strace.log"
	bun_log="$LOGDIR/attempt-$i-$ts.bun-output.log"

	# strace's own filter here is deliberately broader than the original
	# issue's filesystem-only trace (mkdirat/rename/unlink...): `network`
	# covers connect/send*/recv*/socket lifecycle, to test the
	# connection-drop theory from #40063, not just the older directory-race
	# theory. -yy resolves fds to paths/socket info; -s 256 avoids
	# truncating buffer previews to strace's 32-byte default.
	set +e
	strace -f -tt -yy -s 256 \
		-e trace=network,read,write,close,openat,unlinkat,renameat,renameat2 \
		-o "$strace_log" -- bun install >"$bun_log" 2>&1
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
