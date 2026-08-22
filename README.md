# devcontainer-effect

Fully self-scaffolding Dev Container for Bun + [Effect](https://effect.website)
projects. Verified end-to-end against `~/lab/effectLab/first-effect-app` and
by a real build-and-run test (see `.devcontainer/scaffold.sh`'s history for
what that caught).

`Dockerfile` and `devcontainer.json` live in `.devcontainer/` (the path Dev
Containers actually looks for). The top-level copies are symlinks into that
folder, kept only so the files are visible in Finder and plain `ls` without
opening a dot-folder. Because they're symlinks, not copies, editing either
path edits the same file.

## Use in a new project

```bash
cp -r ~/lab/devcontainer-effect/.devcontainer <new-project-root>/
```

That's it — open the folder in a Dev Container. Everything else happens
automatically the first time `postCreateCommand` runs (`.devcontainer/scaffold.sh`):

- `package.json` (Effect/tsgo/oxlint deps, `prepare`/`lint` scripts — see
  "Package versions" below), if missing
- `tsconfig.json` with the Effect Language Service plugin pre-configured
- `.oxlintrc.json`, `.gitignore`, `AGENTS.md`
- `.vscode/settings.json` (native-preview settings + `repos/**` excludes)
- `index.ts` entrypoint — only for a genuinely new project (i.e. only when
  `package.json` was also missing; never added next to an existing project's
  own layout)
- `repos/effect`: Effect's own source, vendored via `git subtree`, for
  coding agents to read as reference (see "Vendored Effect source" below).
  Runs `git init` + an initial commit first if the project isn't a git repo
  yet — `git subtree` needs a HEAD to attach its merge commit to. See "Git
  identity for scaffold commits" below for who that commit (and the
  subtree's) ends up authored as.
- `bun install` (which runs the `prepare` script, patching `typescript` →
  tsgo, `oxlint` → its tsgo-compatible build, etc.)

Every step checks before writing, so re-running this on container rebuild
(or opening an already-scaffolded project) is a no-op past `bun install`.
The first container creation is slower than a rebuild, since it clones the
Effect repo — don't be alarmed if `postCreateCommand` takes a minute or two.

The Claude Code CLI is already installed in the image (see "Claude Code CLI"
below) — open a terminal in the container and run `claude` to sign in. Auth
persists across rebuilds via a per-project named volume, so you only sign in
once per project.

## Git identity for scaffold commits

`scaffold.sh` runs `git init` + an initial commit (and the `repos/effect`
subtree adds two more) on a fresh project, which needs a git identity —
and none is guaranteed to exist inside the container. VS Code's Dev
Containers extension copies your host `~/.gitconfig` in by default, but
that's VS Code-specific behavior, not something this template controls, so
it doesn't cover the `devcontainer` CLI, CI, or a host with
`copyGitConfig` off. Bind-mounting `~/.gitconfig` directly was considered
and rejected — it hard-fails container *creation* if that file doesn't
exist on the host, which is worse than the problem it solves.

Instead, `devcontainer.json` passes your identity in as plain env vars
(`containerEnv`), read from your host shell environment via
`${localEnv:...}` — which resolves to an empty string, not an error, when
unset. Add this once to `~/.zshrc` (or equivalent), then open a new
terminal or `source` it:

```bash
export HOST_GIT_NAME="$(git config --global user.name)"
export HOST_GIT_EMAIL="$(git config --global user.email)"
```

`scaffold.sh` uses these if present; if they're unset (or you skip this
step entirely), it falls back to a repo-local — never `--global` — identity
(`Dev Container <bun@localhost>`), so the scaffold commit never fails, it
just won't be attributed to you.

## Package versions

devDependencies track the `latest` npm dist-tag, dependencies track `effect`
at the `rc` tag (the 4.x prerelease line — `latest` on npm is still 3.x
stable) — **with two pinned exceptions**:

- `oxlint` is pinned to `1.78.0` exactly, not `latest`. This isn't stale —
  `@effect/tsgo@0.36.5` only supports oxlint `1.77.0`/`1.78.0`;
  `oxlint@latest` (1.79.0 as of writing) fails `effect-tsgo patch` with
  `UnsupportedTargetPackageVersionError`. This was caught by actually
  running the scaffold end-to-end in a container, not assumed — re-verify
  against `@effect/tsgo`'s supported range before bumping it past 1.78.0.
- `oxlint-tsgolint` is pinned to `7.0.2001`, not `latest`. This is what
  `bunx @effect/tsgo setup` itself resolves and writes when run against this
  exact dependency set (`@effect/tsgo@0.36.5` + `oxlint@1.78.0`) — treat it
  as tied to those versions, not an independent floating pin; re-run
  `@effect/tsgo setup` and take whatever it resolves if either bumps.

## Vendored Effect source (`repos/effect`)

Per [this technique](https://www.effect.website/blog/the-one-weird-git-trick-that-makes-coding-agents-more-effect-ive):
coding agents work better from real source than from docs written for
humans. `repos/effect` is Effect's own repo, squash-merged in via
`git subtree add --prefix=repos/effect https://github.com/Effect-TS/effect.git main --squash`,
excluded from the TS program (`tsconfig.json`'s `exclude`) and from the
editor's search/watch/auto-import (`.vscode/settings.json`) since it's
read-only reference material, never imported from directly. `AGENTS.md`
points agents at `repos/effect/LLMS.md` (written specifically for them) and
spells out the read-only rule. To refresh it later:
`git subtree pull --prefix=repos/effect https://github.com/Effect-TS/effect.git main --squash`.

Not vendored into this template repo itself (`~/lab/devcontainer-effect`
has no `repos/effect`) — it's scaffolded per-project only, since it's a
real ~17MB+ fetch each time and belongs to the project it's read alongside,
not to the template.

## `customizations.vscode.extensions`

Baked in, not left opt-in, since every project from this template is an
Effect project:

- `oven.bun-vscode`: Bun runtime support
- `oxc.oxc-vscode`: oxlint/oxfmt integration
- `TypeScriptTeam.native-preview`: speaks tsgo's native protocol. Required
  because `effect-tsgo patch` replaces `node_modules/typescript` with tsgo
  (TS 7), which ships no `lib/tsserver.js` — the built-in TS extension
  can't find a server there and silently falls back to its own bundled
  TypeScript instead of the project's. `.vscode/settings.json`'s
  `js/ts.experimental.useTsgo` + `js/ts.tsdk.path` are what make this
  extension actually take over.
- `effectful-tech.effect-vscode` ("Effect Dev Tools"): fiber/span/metrics
  debugging panels. No required settings — its contributed settings
  (`effect.devServer.port`, `effect.metrics.pollInterval`,
  `effect.tracer.pollInterval`, `effect.spanStack.ignoreList`,
  `effect.instrumentation.injectNodeOptions`,
  `effect.instrumentation.injectDebugConfigurations`) are debug-tuning
  knobs with working defaults.
- `anthropic.claude-code`: VS Code panel for the Claude Code CLI installed
  in the Dockerfile (see "Claude Code CLI" below).

## Claude Code CLI

Installed via the [native installer](https://claude.ai/install.sh), not
`npm install -g` — this base image (`oven/bun:debian`) has no real
Node.js/npm, only the `node -> bun` compat symlink described above under
"CLI tools". The installer drops a self-updating binary at
`~/.local/bin/claude`, symlinked to `/usr/local/bin/claude` (same pattern
as the `fd`/`node` symlinks: a Docker `ENV PATH` addition is silently
dropped by Debian's `/etc/profile` for login shells, so symlinking into an
already-on-PATH directory is what actually works in every shell invocation
mode).

Run `claude` in the integrated terminal to sign in the first time. Auth,
settings, and session history persist across container rebuilds via a
named volume mounted at `~/.claude` and keyed by `${devcontainerId}`, so
each project gets its own — see `devcontainer.json`'s `mounts` and
`containerEnv.CLAUDE_CONFIG_DIR`.

## CLI tools

Beyond `git`, `curl`/`wget`/`jq`/`yq` (data fetching/processing),
`ripgrep`/`fd`/`fzf`/`tree` (search/navigation), `vim`/`htop` (editor/process
viewer), and `unzip`/`zip` (archives) are installed in the base image —
selected by category, not just dumped in wholesale. Two package-name
gotchas worth knowing if you ever touch this list:

- `fd`'s Debian package is `fd-find`, and it installs its binary as
  `fdfind` (the name `fd` was already taken by an unrelated package) — the
  Dockerfile symlinks `fd -> fdfind`, same pattern as the `node -> bun`
  symlink above it.
- `yq`'s Debian package resolves to v3.4.3, the old Python/jq-wrapper `yq`
  from ~2020 with its own filter syntax. The `yq` everyone means today —
  YAML-native syntax, jq-compatible, the one used in CI pipelines
  everywhere — is `mikefarah/yq` v4+, distributed only via GitHub releases.
  The Dockerfile fetches it directly with `curl` instead of `apt-get`,
  using Buildx's automatic `TARGETARCH` build arg so it resolves the right
  binary per architecture.

## Effect Language Service (`@effect/language-service`)

Not a VS Code extension — a TypeScript language-service *plugin*,
configured via `tsconfig.json`'s `compilerOptions.plugins` (a
`tsconfig.json`-only concept, hence not in `devcontainer.json` or
`settings.json`). Runs inside whichever TS server is active. Scaffolded
pre-configured; only takes effect once `bun install` has actually installed
the matching devDependency, which `scaffold.sh` handles.
