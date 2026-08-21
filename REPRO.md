# Reproducing oven-sh/bun#39972

This branch exists only to give the Bun maintainers a runnable reproduction
for [oven-sh/bun#39972](https://github.com/oven-sh/bun/issues/39972)
(cross-linked from [#39716](https://github.com/oven-sh/bun/issues/39716)).
It is not meant to be merged — `main` stays pinned to Bun 1.3.14 with no
build-arg, since a project template shouldn't invite accidentally building
against a known-bad version.

## What's different from `main`

`.devcontainer/Dockerfile` takes a `BUN_VERSION` build-arg (default
`1.3.14`, matching `main`'s hard pin) instead of a literal version in the
`FROM` line. Nothing else changed.

## Reproduce the failure (Bun 1.4.0)

```sh
git clone -b bun-1.4.0-tarball-repro https://github.com/RezaOwliaei/devcontainer-effect.git
cd devcontainer-effect
docker build --build-arg BUN_VERSION=1.4.0 -f .devcontainer/Dockerfile -t bun-repro .devcontainer

mkdir /tmp/repro && cd /tmp/repro
cat > package.json <<'EOF'
{
  "dependencies": {
    "@effect/experimental": "latest",
    "effect": "rc"
  },
  "devDependencies": {
    "@effect/language-service": "latest",
    "@effect/tsgo": "latest",
    "@types/bun": "latest",
    "oxfmt": "latest",
    "oxlint": "1.78.0",
    "oxlint-tsgolint": "latest",
    "typescript": "latest"
  }
}
EOF

docker run --rm -v "$(pwd)":/work -w /work bun-repro bun install
```

Expect (intermittently — roughly 1 in 6 attempts in our testing, so it may
take a couple of tries): `error: Fail extracting tarball for "effect"`.

## Confirm the fix (Bun 1.3.14 — the default)

Same steps, but build without the `--build-arg` override (or pass
`--build-arg BUN_VERSION=1.3.14` explicitly):

```sh
docker build -f .devcontainer/Dockerfile -t bun-1.3.14 .devcontainer
docker run --rm -v "$(pwd)":/work -w /work bun-1.3.14 bun install
```

Installs cleanly every time in our testing.

## Full strace-backed root-cause analysis

See the issue body and the linked `strace -f -tt` log in the issue's
comments for the syscall-level trace pinpointing the race (a worker thread
removing `effect`'s temp extraction directory by name while another thread
is still writing into it, before the rename-into-place step).
