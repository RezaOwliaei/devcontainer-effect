# THIS BRANCH exists only to hunt oven-sh/bun#39972 under strace for the
# maintainers — see STRACE-REPRO.md. Not meant to be merged to main: hard
# pins 1.4.0 (the known-bad version) on purpose, with no build-arg toggle,
# since the whole branch has exactly one job.
#
# Base: official Bun image, Debian (trixie) variant — has apt-get. Multi-arch
# manifest: resolves natively to linux/arm64 on Apple Silicon, linux/amd64
# elsewhere — no --platform override needed.
#
# This is a genuinely minimal image: it does NOT include ca-certificates,
# curl, or git by default (verified empirically, don't trust descriptions of
# it) — all handled explicitly below.
FROM oven/bun:1.4.0-debian

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
# strace: THIS BRANCH ONLY — syscall/network tracing for the #39972 hunt in
# scaffold.sh. Needs SYS_PTRACE + a permissive seccomp profile at container
# runtime too (see devcontainer.json), or it fails with "Operation not
# permitted" even as a non-root user tracing its own child.
RUN apt-get update -qq \
    && apt-get install -qq --no-install-recommends -y \
        git ca-certificates bash-completion locales \
        curl wget jq ripgrep fd-find fzf tree vim htop unzip zip strace \
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

# Pre-create the bun install cache dir and the Claude Code config dir,
# owned by bun, BEFORE their named volume mounts happen (those are
# controlled by devcontainer.json, at container creation time, not build
# time — but Docker seeds a fresh named volume's ownership/contents from
# whatever already exists at that path in the image). Skipping this is
# what causes "bun is unable to write files to tempdir: AccessDenied" for
# the Bun cache, and the equivalent for Claude Code's ~/.claude: an
# unmounted path with no prior image content gets created as root:root
# when the volume first mounts, and the bun user (uid 1000) can't write
# into it.
RUN mkdir -p /home/bun/.bun/install/cache /home/bun/.claude \
    && chown -R bun:bun /home/bun/.bun /home/bun/.claude

# Claude Code CLI: native installer, not npm (this image ships no real
# Node.js/npm, only the node -> bun compat symlink above). Run via `su -
# bun` while still root so HOME resolves to /home/bun and the installed
# files (~/.local/bin/claude, ~/.local/share/claude/versions/) end up
# owned by bun, not root. Then symlinked into /usr/local/bin (root-owned,
# so this has to happen before USER bun below) rather than added to PATH,
# for the same reason as the node -> bun symlink above: a Docker ENV PATH
# addition is silently dropped by Debian's /etc/profile for login shells.
# The native installer self-updates in the background independent of this
# image layer, so a session always runs the latest Claude Code regardless
# of when the container was last rebuilt.
RUN su - bun -c "curl -fsSL https://claude.ai/install.sh | bash" \
    && ln -s /home/bun/.local/bin/claude /usr/local/bin/claude

# Run as the image's built-in non-root `bun` user (uid 1000/gid 1000) rather
# than root, per Dev Container convention. The base image creates this user
# but doesn't activate it by default.
USER bun

# --- Project-specific additions go below this line, e.g.: ---
# RUN apt-get update -qq && apt-get install -qq --no-install-recommends -y <pkg> && ...
