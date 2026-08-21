# Agent instructions

This project vendors Effect's own source at `repos/effect` via `git subtree`
(see the [technique writeup](https://www.effect.website/blog/the-one-weird-git-trick-that-makes-coding-agents-more-effect-ive)
this setup follows). Coding agents are more effective reading real source
and following existing patterns than working from documentation written for
humans, and vendoring it locally is more token-efficient than fetching docs
over the web on demand.

- **Before writing any Effect code**, read `repos/effect/LLMS.md` first —
  it's written specifically for coding agents.
- Treat `repos/effect` as **read-only reference material**. Never edit
  files there and never import from it directly — it's excluded from the
  TypeScript program (`tsconfig.json`'s `exclude`) and from the editor's
  search/watch/auto-import (`.vscode/settings.json`) for exactly this
  reason: it's for reading, not for the build.
- Prefer examples and patterns found in `repos/effect` (real, working,
  version-matched code) over remembered API shapes, which may be stale
  relative to the exact Effect version this project pins.
- To refresh the vendored copy after Effect ships updates:
  `git subtree pull --prefix=repos/effect https://github.com/Effect-TS/effect.git main --squash`
