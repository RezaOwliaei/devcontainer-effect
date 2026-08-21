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

# Vendor Effect's own source for agent reference (see AGENTS.md) — this is
# a real network fetch of the Effect repo, so first container creation is
# slower than a later rebuild once repos/effect already exists.
if [ ! -d repos/effect ]; then
	git subtree add --prefix=repos/effect https://github.com/Effect-TS/effect.git main --squash
fi

bun install
