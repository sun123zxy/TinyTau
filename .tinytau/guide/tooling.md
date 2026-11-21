---
name: Local Tooling, CI, and Documentation Guide
description: Explains how TinyTau uses Lean, doc-gen4, Quarto, and Git scripts, and how to run roadmap comparison and site generation locally.
---

## Toolchain Overview

TinyTau relies on a small set of standard tools shared between local execution and GitHub Actions CI:

- **Lean 4 & Lake (`lean-action.yml`)**: Compiles the Lean library (`lake build --wfail`) and runs [`leanprover-community/axiom-audit`](https://github.com/leanprover-community/axiom-audit) to verify that every declaration depends only on Lean's three standard axioms (`propext`, `Classical.choice`, `Quot.sound`), catching any `sorryAx` (`sorry`/`admit`), `Lean.ofReduceBool` (`native_decide`), or custom `axiom`s.
- **Upstream Roadmap Integrity (`compare-human.sh`)**: Uses pure `git` tree diffs to verify that all human-authored files under `roadmap/` (every file whose stem does not end in `-ai`) match `human-repo` at `.tinytau/sync.yml`'s `human-sha` byte-for-byte.
- **API Documentation (`docgen-action` in CI / `build-docs.sh` locally)**: GitHub Actions ([`.github/workflows/pages.yml`](/.github/workflows/pages.yml)) builds and caches [`doc-gen4`](https://github.com/leanprover/doc-gen4) API reference pages into `_site/docs/` and deploys `_site/` to GitHub Pages on every `push` to `main` or `master` via [`leanprover-community/docgen-action`](https://github.com/leanprover-community/docgen-action). Locally, `build-docs.sh` + `parse-lake-metadata.py` remain available to build `_site/docs/` in a temporary `docbuild/` Lake workspace for previewing.
- **Roadmap Rendering (`build-roadmap.sh` + `tinytau.lua`)**: Uses [Quarto](https://quarto.org/) to render `roadmap/` into `_site/roadmap/`. During rendering, `.tinytau/scripts/tinytau.lua` hooks into Quarto's `pre-ast` filter stage (`quarto.doc`, `quarto.project.offset`, `quarto.utils`), reads each document's paired `<stem>-ai.yml` sidecar, and appends a `.tinytau-meta` block (`Status`, `docs` links, `Depends` links, and `Note` with Quarto `@crossref` support) to the end of each matching `::: {#id}` block.

## Automatic Worker Pushes

The [worker](/.tinytau/prompt/worker.md#automatic-pushes) checks the interval before automatically pushing. Configure it with `push-min-interval` in [`.tinytau/config.yml`](/.tinytau/config.yml). The default is 10 minutes and `0` disables the interval. The last successful automatic push time is local to the clone. A later worker invocation can publish deferred commits. Manual `git push` remains available.

## Running `compare-human` Locally

To verify locally that your `HEAD` commit has not modified any human-authored files under `roadmap/` relative to `.tinytau/sync.yml`:

```sh
bash .tinytau/scripts/compare-human.sh
```

- **Requirements**: `bash`, `git`, `awk`, `sed`.
- **Behavior**:
  - Reads `human-repo` and `human-directory` from [`.tinytau/config.yml`](/.tinytau/config.yml) and `human-sha` from [`.tinytau/sync.yml`](/.tinytau/sync.yml).
  - If `human-sha` is `null`, checks that no human-authored files exist under `HEAD:roadmap`.
  - Otherwise, fetches `human-sha` from `human-repo` (if not already cached locally) and runs `git diff` against `HEAD:roadmap`, ignoring `*-ai.*` files.

## Building Docs and Roadmap Locally

Both parts of the GitHub Pages site (`.github/workflows/pages.yml`) can be built locally into `_site/` (which is git-ignored).

### Build `doc-gen4` API Docs (`_site/docs/`)

Ensure your Lean project builds cleanly first, then run `build-docs.sh`:

```sh
lake build --wfail
bash .tinytau/scripts/build-docs.sh
```

- **Requirements**: `bash`, `lake` (or `~/.elan/bin/lake`), `python3` (3.11+ for standard-library `tomllib`).
- **Output**: Creates/updates `docbuild/` and copies the generated HTML documentation into `_site/docs/` (so `/docs/<Module>.html#<Decl>` links in `*-ai.yml` resolve to `_site/docs/<Module>.html#<Decl>`).

### Render Quarto Roadmap (`_site/roadmap/`)

Run `build-roadmap.sh` to render `roadmap/` with `*-ai.yml` metadata injected into each target block:

```sh
bash .tinytau/scripts/build-roadmap.sh
```

- **Requirements**: `bash`, `quarto`.
- **Behavior**:
  - Copies `roadmap/` into a temporary working directory so your working tree's `roadmap/` stays untouched.
  - Provides a fallback `_quarto.yml` if `roadmap/` does not already contain one, forces `--output-dir _site/roadmap`, and injects `.tinytau/scripts/tinytau.lua` at Quarto's `pre-ast` entry point.
  - Reads `quarto-profile` from [`.tinytau/config.yml`](/.tinytau/config.yml) and passes `--profile <quarto-profile>` when non-empty.
- **Output**: Writes the rendered HTML roadmap into `_site/roadmap/`.

### Preview the Combined Site Locally

After running either or both build scripts, copy the root landing page (`.tinytau/page/index.html`) and serve `_site/` with any static HTTP server from the repository root:

```sh
cp -r .tinytau/page/. _site/
python3 -m http.server 8000 --directory _site
```

Then open:

- `http://localhost:8000/` for the root landing page.
- `http://localhost:8000/roadmap/` for the rendered roadmap (with interactive `/docs/...` and `/roadmap/...` links).
- `http://localhost:8000/docs/` for the `doc-gen4` Lean API reference.
