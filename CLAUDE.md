# PHAVerLite IDE (lem-based)

A Common Lisp IDE for editing PHAVerLite hybrid-automaton models (`.pha` files),
built on top of the [lem](https://github.com/lem-project/lem) editor. The IDE wraps
the existing `phaverlite` CLI workflow (currently driven by ad-hoc shell scripts)
in an interactive editor with a small custom Language Server Protocol (LSP)
implementation.

## Goals (first prototype)

1. **Editing** — syntax-aware editing of `.pha` files (PHAVer modeling language).
2. **PC sweep UI** — interactive, friendly version of `Lab3/sweep_pc.sh`: pick a
   template, choose a range / step for the partition-constraint parameter `pc`,
   run `phaverlite` for each value, show results (reachable / unreachable, CPU time)
   in a results buffer.
3. **Plot generation** — invoke `plotutils` (`graph`, etc.) on PHAVerLite output
   to produce reachable-set / invariant plots, displayed or saved alongside the
   model.
4. **Tiny LSP** — a project-local language server providing at least:
   diagnostics (parse errors, missing `end`, unknown identifiers),
   document symbols (automata, locations), hover for keywords. No external LSP
   framework required — speak JSON-RPC over stdio directly.

Installation packaging for end users is **out of scope** for the prototype.

## Hard self-containment rule

Everything except these three external dependencies must live under this repo:

- `phaverlite` executable (system-installed via `ps3/install_phaverlite.sh`)
- `sbcl` (Common Lisp implementation)
- `plotutils` (`graph` and friends)

All three are already installed on the development Mac, so the IDE may assume
they are on `PATH` — no bootstrap step required for them.

`qlot` is also assumed to be installed on the developer machine (Roswell:
`~/.roswell/bin/qlot`). We treat it as a build tool (like `make`), not as a
runtime dependency of the IDE.

That means the following all live inside the repo, **not** in `~/.config/lem/`,
`~/quicklisp/`, `~/.sbclrc`, etc.:

- All Common Lisp dependencies, including `lem` itself, managed by **qlot**
  (`qlfile` + `qlfile.lock` at repo root, install dir `<repo>/.qlot/`). Lem is
  pinned to a specific git SHA via a `git` entry in `qlfile` so builds are
  reproducible. We do **not** check a copy of lem into `vendor/` unless we
  need to patch lem itself; in that case, `vendor/lem/` is added and qlfile
  points at it.
- Lem `init.lisp` (e.g. `config/init.lisp`).
- Our IDE Lisp code (asd files at repo root, sources in top-level folders
  like `src/`, per the ASDF-layout convention below), exposed to the Lisp
  image as ASDF systems registered through qlot's per-project
  `local-projects` mechanism (or `CL_SOURCE_REGISTRY`).
- The launch script that boots SBCL via `qlot exec` with the right `--load`
  chain.

Use environment variables in the launcher (`LEM_HOME`, `XDG_CONFIG_HOME`,
`XDG_DATA_HOME`, etc.) pointed at directories inside this repo so neither
lem nor sbcl escape the project dir at runtime.

### qlot footprint outside the repo (intentional, minimal)

By design, `qlot install` writes only to `<repo>/.qlot/`. Two pre-existing
qlot-related dirs in `$HOME` are **left strictly alone**:

- `~/.qlot/local-projects/` — qlot's optional global shared-local-projects
  override. We never write here. The IDE must not put any project-specific
  Lisp source there.
- `~/.cache/qlot/` — qlot's download cache for distribution tarballs.
  Analogous to `~/.npm` or `~/.cargo/registry`. Benign, shared across all qlot
  projects, contains no project state. We let it function normally.

If anything we do would write to `~/.qlot/`, that is a bug.

### Why qlot

- Per-project pinned deps in `qlfile.lock`; reproducible across machines.
- Installs into `<repo>/.qlot/` — no global QL or `~/.sbclrc` edits.
- First-class git pinning (lem moves fast; we want a known-good SHA).
- `qlot exec sbcl …` is the canonical "run with this project's deps" pattern,
  which becomes our launcher.

The alternative — hand-vendoring Quicklisp under `vendor/quicklisp/` and
dropping a lem clone into `local-projects/` — works but reimplements qlot
poorly and is harder to update. Since qlot is already available, we use it.

## Repo layout (intended)

```
.
├── CLAUDE.md                this file
├── qlfile                   qlot dep manifest (lem pinned by git SHA, etc.)
├── qlfile.lock              qlot lockfile (committed)
├── .qlot/                   qlot install dir (gitignored; created by `qlot install`)
├── bin/
│   └── phaverlite-ide       launcher script: env + `qlot exec sbcl --load …`
├── config/
│   └── init.lisp            lem init: load our packages, keybindings
├── src/
│   ├── phaverlite-mode/     major mode for .pha (syntax, indent, commands)
│   ├── phaverlite-lsp/      LSP server (separate ASDF system)
│   ├── pc-sweep/            sweep UI + runner
│   └── plot/                plotutils integration
├── vendor/                  only used if we need to patch a dep (e.g. lem)
├── ps3/                     reference: PS3 problem + sample .pha
│   └── ps3.pdf              spec — authoritative
└── Lab3/                    reference: Lab3 problem + heater_template.pha
    ├── Lab3.pdf             spec — authoritative
    └── sweep_pc.sh          existing pc-sweep we are replacing in-IDE
```

## Reference material — handle with care

`ps3/` and `Lab3/` contain **reference inputs and prior attempts**. They are
useful for understanding the file format, the CLI surface of `phaverlite`, and
the shape of expected output. They are **not** ground truth:

- The PDFs (`ps3/ps3.pdf`, `Lab3/Lab3.pdf`) are the authoritative specs.
- Any `.pha` model, output file, or shell script in those dirs may be incorrect,
  partial, or outdated. Do not assume `chen_XXX.pha`, `out_*` files, or
  `sweep_pc.sh` produce the right answer for the spec — re-derive from the PDF
  when correctness matters.

## PHAVerLite invocation (what the IDE wraps)

```
phaverlite path/to/model.pha
```

`phaverlite` writes results to stdout/stderr. The pc-sweep workflow patches a
single `__PC__` placeholder in a template `.pha`, runs `phaverlite` on the
materialized file, then greps stdout for:

- `bad not reachable` → unreachable
- `bad is reachable`  → reachable
- `Time in get_reach_set` → CPU time (penultimate field on the last match)

The IDE should preserve this contract but expose it as a buffer/UI rather than
a shell loop.

## Conventions

- Common Lisp. **ASDF layout follows lem's convention:** the `.asd` file
  lives at the repo root with `:pathname "src"` (or another top-level
  source folder), and the source files sit directly under that folder —
  no extra project-name subdirectory. When the repo grows multiple ASDF
  systems, add new top-level source folders (mirroring lem's
  `extensions/`, `frontends/`, `contrib/`) rather than nesting under `src/`.
- **Inline package definitions. No `package.lisp` files.** Every `.lisp`
  file starts with `(defpackage …)` immediately followed by `(in-package …)`
  for the package that file belongs to. Default is one package per file.
  When a module grows large enough to split across multiple files, those
  files naturally share a single package — that's a normal growth pattern,
  not a special case. Never aggregate `defpackage` forms into a separate
  `package.lisp`. This applies to all CL we write and to anything
  subagents/skills generate on our behalf.
- **Package names use lem's `/` sub-module style**, e.g.
  `phaverlite-mode/syntax`, not Java-style `phaverlite-mode.syntax`.
- No global writes: never touch `~/.sbclrc`, `~/.config/lem/`, system quicklisp.
- `.pha` is a C-style syntax (`//` comments, `;` terminators, `loc … :` blocks,
  `automaton … end`). Treat it as its own language — do not reuse a generic
  C/Lisp mode.
- Test models from `ps3/` and `Lab3/` are the smoke-test corpus. The pc-sweep
  feature must reproduce the row format of `Lab3/sweep_pc.sh`
  (`pc | result | cpu(s)`).

## Privacy & security (this is a public repo)

The repo is hosted publicly on GitHub. Treat every committed file as
world-readable forever. Hard rules for anything that gets staged:

- **No personal absolute paths.** Never write `/Users/<name>/...` or
  `/home/<name>/...` into tracked files (scripts, configs, docs, code).
  Use `$HOME`, `~`, or repo-relative paths. The launcher derives its own
  location with `$(dirname "$0")` rather than hardcoding.
- **No real names of collaborators, classmates, or instructors** in code,
  docs, filenames, or commit messages. Use placeholders (e.g.
  `chen_XXX.pha`) when referring to coursework files. Real-name files stay
  in the gitignored `ps3/` and `Lab3/` directories.
- **No coursework content.** `ps3/` and `Lab3/` (PDFs, sample `.pha`,
  prior-attempt `out_*` files, classmate-named zips, install scripts that
  may have been distributed under course terms) are gitignored. Do not
  copy their contents into tracked files. The IDE may *read* them at
  runtime; it must not bake them into source.
- **No secrets, tokens, API keys, SSH keys, `.env` files** — even
  placeholder ones. The `.gitignore` covers the obvious patterns; do not
  override with `git add -f`.
- **No identifying metadata leaks.** Don't commit `.DS_Store`, editor
  swap files, shell history, or local caches. Don't put the developer's
  email or machine hostname in scripts or docs.
- **Generated outputs stay local.** PHAVerLite reachability dumps and
  plot files are reproducible from the `.pha` source; they don't need to
  be committed and may inadvertently contain absolute paths from
  `phaverlite`'s working directory.
- **Before every commit:** run `bin/privacy-preflight staged` (or
  `bin/privacy-preflight unpushed` before pushing). The script greps a
  baseline pattern (paths, generic email domains, secrets keywords)
  PLUS any project-specific tokens loaded from `.privacy-patterns`
  (gitignored sidecar — real names, classmate handles, personal email
  fragments, etc.). Exits 0 on clean, non-zero on match.
- **Never inline a grep with sensitive tokens** in committed scripts,
  docs, plans, or commit messages. The grep pattern itself ends up in
  git history — defeating the purpose. Always shell out to
  `bin/privacy-preflight`.

If something sensitive does land in a commit, treat it as compromised:
rotate the secret, and if it's already pushed, rewrite history with
`git filter-repo` (or accept that it's public forever — git rewrites do
not fully erase data on GitHub).

## Status

Bootstrapping. Nothing built yet. CLAUDE.md and `.gitignore` are the
first artifacts.
