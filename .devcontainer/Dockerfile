# Base: official Bun image, Debian (trixie) variant — has apt-get. Multi-arch
# manifest: resolves natively to linux/arm64 on Apple Silicon, linux/amd64
# elsewhere — no --platform override needed. Deliberately unpinned (`debian`,
# not a version tag): this is a lab template meant to track Bun's latest
# release, not a reproducible-build target.
#
# History: was pinned to 1.3.14 for a while because 1.4.0 intermittently
# failed `bun install` on this template's dependency set with `error: Fail
# extracting tarball for "effect"` (~1/17 fresh-container attempts, not
# consistently reproducible — see oven-sh/bun#39972, root-caused to a
# streaming-tarball-extraction fault, not anything specific to this
# project). Unpinned again because the failure rate is low enough to accept
# and Bun has a fix in flight (oven-sh/bun#39986, open as of writing: retries
# a failed streaming extraction through a safer buffered path instead of
# failing outright). If `bun install` starts failing with "Fail extracting
# tarball" again, that issue/PR pair is the first place to check before
# re-pinning.
#
# This is a genuinely minimal image: it does NOT include ca-certificates,
# curl, or git by default (verified empirically, don't trust descriptions of
# it) — all handled explicitly below.
FROM oven/bun:debian

# node -> bun symlink so anything shelling out to `node` (npm-ecosystem CLIs
# with a `#!/usr/bin/env node` shebang — oxlint-tsgolint, oxfmt, etc.) works
# without a real Node.js install. Placed in /usr/local/bin specifically: it's
# on PATH in every shell invocation mode tested (login, non-login, sh) —
# unlike a Docker ENV PATH addition, which Debian's /etc/profile silently
# clobbers for login shells.
RUN ln -s /usr/local/bin/bun /usr/local/bin/node

# git: for repo operations from the integrated terminal.
# ca-certificates: required for git's HTTPS backend — without it, git fails
# with "Problem with the SSL CA cert" (confirmed empirically; this base image
# has no CA bundle at all despite git itself being usable once installed).
# bash-completion: the base image's `bun` user has its login shell set to
# /bin/sh (dash), which has no tab-completion at all — not a missing config,
# a different program. Installed here; wired up below once the shell is
# switched to bash.
# locales: bash (unlike dash) actually calls setlocale() on startup, so
# without a generated locale every interactive shell prints "bash: warning:
# setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8)" — cosmetic, but
# also the kind of thing that quietly breaks UTF-8 handling in some CLIs.
# curl/wget: HTTP fetches, API testing, downloads (curl is also needed below
# to fetch yq).
# jq/yq: JSON/YAML processing from the shell.
# ripgrep/fd-find/fzf/tree: fast search and navigation.
# vim/htop: terminal editor and process viewer.
# unzip/zip: archive handling — no zip support at all otherwise.
RUN apt-get update -qq \
    && apt-get install -qq --no-install-recommends -y \
        git ca-certificates bash-completion locales \
        curl wget jq ripgrep fd-find fzf tree vim htop unzip zip \
    && update-ca-certificates \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen \
    && locale-gen \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Debian's fd-find package installs its binary as `fdfind`, not `fd` — the
# name `fd` was already taken by an unrelated package, so Debian renamed
# this one to avoid the clash. Same fix as the node -> bun symlink above:
# alias it to the name everyone actually types.
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd

# Debian's `yq` apt package is the old Python/jq-wrapper yq (v3.4.3, last
# released ~2020, its own filter syntax closer to jq than YAML-native). The
# yq everyone means today — YAML-native syntax, jq-compatible, used in CI
# pipelines everywhere — is mikefarah/yq v4+, a single Go binary distributed
# only via GitHub releases, not apt. TARGETARCH is a Buildx-provided
# automatic build arg (resolves to arm64/amd64), matching how this base
# image already resolves natively per-arch with no manual --platform
# override needed.
ARG TARGETARCH
RUN curl -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH}" \
    && chmod +x /usr/local/bin/yq

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Switch the bun user's login shell from /bin/sh to /bin/bash (already
# present in the base image, just unused) so the integrated terminal gets
# real line editing and tab-completion — filenames, git subcommands/branches
# (via bash-completion above), etc. Debian's bash reads /etc/bash.bashrc for
# every interactive shell, which sources bash-completion automatically once
# the package is installed, so no per-user rc file edits are needed.
RUN usermod --shell /bin/bash bun

# Pre-empt git's "detected dubious ownership" error, which fires whenever the
# bind-mounted workspace's on-disk uid doesn't match the container user (seen
# on some Docker Desktop / Linux-host combinations — not guaranteed, but free
# to fix here and impossible to work around from inside a broken terminal).
# Scoped to /workspaces rather than "*" so it doesn't blanket-trust every path.
RUN git config --system --add safe.directory '/workspaces/*'

# Pre-create the bun install cache dir, owned by bun, BEFORE the named
# volume mount happens (that's controlled by devcontainer.json, at container
# creation time, not build time — but Docker seeds a fresh named volume's
# ownership/contents from whatever already exists at that path in the
# image). Skipping this step is what causes
# "bun is unable to write files to tempdir: AccessDenied": an unmounted path
# with no prior image content gets created as root:root when the volume
# first mounts, and the bun user (uid 1000) can't write into it.
RUN mkdir -p /home/bun/.bun/install/cache && chown -R bun:bun /home/bun/.bun

# Run as the image's built-in non-root `bun` user (uid 1000/gid 1000) rather
# than root, per Dev Container convention. The base image creates this user
# but doesn't activate it by default.
USER bun

# --- Project-specific additions go below this line, e.g.: ---
# RUN apt-get update -qq && apt-get install -qq --no-install-recommends -y <pkg> && ...
