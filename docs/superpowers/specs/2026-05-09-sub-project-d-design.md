# Sub-project D — `plot` (plotutils integration)

**Date:** 2026-05-09
**Status:** Approved design, not yet implemented
**Scope:** Fourth of five sub-projects. Builds on A, B, C. See `CLAUDE.md`
for the A→B→(C,D,E) decomposition.

## Goal

Render PHAVerLite's reach-set / invariant output as a PNG via GNU plotutils
`graph(1)`, opened in the system viewer (`open` on macOS). Two surfaces:

1. **`M-x phaverlite-plot-buffer`** (or `C-c C-p`) on a `.pha` source — runs
   `phaverlite` in a per-buffer plot directory, then renders + opens the
   plot. For models with `.print("out_reach", N)` lines (e.g.
   `Lab3/bouncing_ball.pha`) that don't necessarily test a reachability
   condition.
2. **`p` on a sweep row** in `*phaverlite-sweep*` — plots the reach-set for
   that row's pc value. Requires a small touch-up to sub-project C: each
   sweep iteration runs in its own per-pc directory so `out_reach`/`out_inv`
   survive across iterations.

Both surfaces share one internal primitive: "render a directory containing
`out_reach` and `out_inv`."

## Definition of done

1. `M-x phaverlite-plot-buffer` (or `C-c C-p`) on a `.pha` buffer:
   - Refuses with `Buffer not visiting a file` if the buffer has no filename.
   - If buffer modified, prompts y/n to save (same shape as
     `phaverlite-run-buffer`).
   - Refuses with `Sweep in progress; use 'p' on a sweep row instead` if
     `phaverlite-mode/sweep:*active-sweep*` is non-nil.
   - Spawns `phaverlite <path>` with cwd set to `var/plot/<basename>/`
     (auto-created).
   - On completion, calls `render-plot-dir` on that directory.
2. `render-plot-dir <dir>` invokes:
   ```
   graph -T png -C -B -q 0.1 <dir>/out_inv -C -q 0.5 <dir>/out_reach > <dir>/plot.png
   ```
   then `open <dir>/plot.png` (macOS), then `lem:message "Plot: <path>"`.
3. `p` keybind in `*phaverlite-sweep*` invokes `phaverlite-sweep-plot-row`:
   - Reads the pc value from the first whitespace-token of the line at point.
   - Looks up `var/sweep/<basename>/pc-<pc>/`. If missing → message and abort.
   - Calls `render-plot-dir` on that directory.
4. Sub-project C touch-up: sweep engine puts each iteration in
   `var/sweep/<basename>/pc-<value>/`; the materialized `.pha` lives there;
   `phaverlite` is spawned with `:directory pc-dir` so `out_reach`/`out_inv`
   land in that dir. The sweep state struct gains a `template-basename`
   slot used by the `p` handler.
5. `bin/test-mode` exits 0 with sub-project B's + sub-project C's existing
   oks (with the touch-up update applied) plus the new D deftests
   (`plot-render`, `plot-buffer-command`, `sweep-plot-row`).
6. `bin/verify-isolation` PASS (no new `$HOME` writes from plot code).
7. Smoke: open `Lab3/bouncing_ball.pha`, `C-c C-p`, see Preview.app pop
   with a plot. Open `Lab3/heater_template.pha`, `C-c C-s` → sweep, then
   `p` on a row → see Preview.app pop with that pc's reach-set.

**Out of scope for D:**
- LSP diagnostics / symbols / hover (sub-project E).
- Configurable plot filenames (we hardcode `out_reach` / `out_inv`; if a
  user's `.pha` uses other names like `out_reachable`, they rename or wait
  for a follow-up that globs / parses the source).
- Plot title or axis labels (`-L` flag dropped from the `graph` invocation).
- Variable-name extraction from the `.pha` source.
- Configurable column selection (we plot columns 1+2 of `out_reach` and
  `out_inv`; the third column is whatever phaverlite emits and `graph`
  ignores it for 2D plots).
- ASCII / dumb-terminal fallback if the system viewer fails (we surface
  the failure via `lem:message` and leave the PNG on disk for manual open).
- Cross-platform display target (macOS `open` only; Linux/Windows users
  can manually open the PNG path printed in `lem:message`).
- Concurrent-plot serialization (two quick `p` presses race on the same
  `plot.png`; `graph` rewrites in place so worst case is a brief stale
  view in Preview).
- Per-plot history beyond the latest `plot.png` (overwrites in place).
- N-D plotting (we hardcode 2D; PHAVer models with > 2 contr_vars project
  to columns 1+2).

## Architecture

Folded into the existing `phaverlite-mode` ASDF system. No new ASDF system.
One new source file (`src/plot.lisp`) and a small touch-up to
`src/sweep.lisp` (per-pc subdirs + buffer-local `p` keybind).
Justification: same as sub-project C — project still small enough that a
separate system would create boundaries that don't earn their keep.

```
src/plot.lisp                  package phaverlite-mode/plot
                                — render-plot-dir (internal primitive)
                                — phaverlite-plot-buffer (interactive command)
                                — phaverlite-sweep-plot-row (interactive command)
                                Exports: phaverlite-plot-buffer
                                         phaverlite-sweep-plot-row
phaverlite-mode.asd            +1 component: (:file "plot") at the end
src/sweep.lisp                 modify: per-pc subdir + spawn phaverlite with
                                :directory pc-dir; add template-basename slot
                                to sweep-state; bind `p` →
                                phaverlite-mode/plot:phaverlite-sweep-plot-row
                                via a buffer-local keymap on *phaverlite-sweep*
                                (the existing *phaverlite-mode-keymap* keeps
                                C-c C-s / C-c C-n / C-c C-k for source buffers)
                                (the C-c C-p define-key goes at the bottom
                                of src/plot.lisp, NOT in src/commands.lisp,
                                same load-order pattern as sub-project C's
                                bindings; src/commands.lisp is unchanged)
tests/main.lisp                +deftests: plot-render, plot-buffer-command,
                                sweep-plot-row
                                update: sweep-engine deftest gains assertion
                                for the new per-pc dir layout
tests/fake-graph               new shell stub for graph; symlinked as `graph`
                                on test PATH
bin/test-mode                  modify: one extra ln -sf line for fake-graph
```

`config/init.lisp` and `bin/build-image` untouched — they already load
`phaverlite-mode`. Image rebuild via `bin/build-image` after wiring.

System-level deps unchanged: still need `phaverlite`, `sbcl`, `plotutils`
(per CLAUDE.md hard self-containment rule). No new lisp deps.

## Components (top-to-bottom inside `src/plot.lisp`)

### State and constants

```lisp
(defparameter +plot-filename+ "plot.png")
(defparameter +reach-filename+ "out_reach")
(defparameter +inv-filename+   "out_inv")
```

Failures and successes surface via `lem:message` only — no audit buffer.
Lem's built-in `*Messages*` already serves as the persistent log.

### Core primitive: `render-plot-dir`

```lisp
(defun render-plot-dir (dir) → pathname-or-NIL
  ;; 1. Validate: dir/out_reach AND dir/out_inv both exist. Missing →
  ;;    lem:message + return NIL.
  ;; 2. Compute output path = dir/plot.png.
  ;; 3. Build the `graph` command:
  ;;      graph -T png -C -B -q 0.1 <dir>/out_inv -C -q 0.5 <dir>/out_reach
  ;;    Run via uiop:run-program; redirect stdout to <dir>/plot.png by
  ;;    opening the file in lisp and passing :output to run-program, OR
  ;;    pass the redirection via a /bin/sh -c wrapper. Both work; pick
  ;;    one at implementation time.
  ;; 4. graph not on PATH → catch, message + return NIL, no open.
  ;; 5. graph exits non-zero → catch, message, leave partial PNG on disk
  ;;    if any, return NIL.
  ;; 6. uiop:launch-program (list "open" (namestring plot-path)) — async,
  ;;    catches any failure (e.g. headless session) and just messages
  ;;    "open failed: <err>; plot at <path>".
  ;; 7. lem:message "Plot: <path>"; return plot-path.
  )
```

### Single-run command: `phaverlite-plot-buffer`

```lisp
(define-command phaverlite-plot-buffer (&optional buffer) ()
  ;; 1. buf = (or buffer (current-buffer)); path = buffer-filename.
  ;; 2. cond: no path → message, return.
  ;;          *active-sweep* non-nil → message "Sweep in progress…", return.
  ;;          modified + n → silent abort.
  ;; 3. modified + y → save-buffer.
  ;; 4. plot-dir = var/plot/<basename>/  (ensure-directories-exist).
  ;; 5. uiop:launch-program (list "phaverlite" (namestring path))
  ;;      :output :stream :error-output :output
  ;;      :directory plot-dir
  ;;    Wait synchronously (uiop:wait-process). Single-run, no
  ;;    cancellation in prototype. Discard stdout (phaverlite's text
  ;;    output isn't useful for plotting).
  ;; 6. (render-plot-dir plot-dir).
  )
```

### Sweep-row command: `phaverlite-sweep-plot-row`

```lisp
(define-command phaverlite-sweep-plot-row () ()
  ;; 1. Verify (current-buffer) is the *phaverlite-sweep* buffer; else
  ;;    message "Not in a *phaverlite-sweep* buffer", return.
  ;; 2. Read the line at point. First whitespace-separated token, parse
  ;;    as float. Parse failure → message "No sweep row at point", return.
  ;; 3. Pull template-basename from a buffer-local var (set by
  ;;    sub-project C's run-sweep when it creates the buffer).
  ;; 4. pc-dir = var/sweep/<basename>/pc-<pc-token>/
  ;;    Use the literal pc-token from the row, NOT a re-formatted float
  ;;    (matches whatever sub-project C wrote when it materialized).
  ;; 5. (probe-file pc-dir) NIL → message "No plot data for pc=<pc> (was
  ;;    it cancelled?)", return.
  ;; 6. (render-plot-dir pc-dir).
  )
```

### Mode keybindings (at bottom of `src/plot.lisp`)

```lisp
(define-key phaverlite-mode/commands:*phaverlite-mode-keymap*
            "C-c C-p" 'phaverlite-plot-buffer)
;; The `p` binding for *phaverlite-sweep* is set up in src/sweep.lisp
;; (after the sweep buffer's keymap exists), referencing this command via
;; phaverlite-mode/plot:phaverlite-sweep-plot-row.
```

## Sub-project C touch-up (`src/sweep.lisp`)

Two changes:

1. **Per-pc subdirs.** `sweep-output-path` changes from
   `var/sweep/<basename>.pha` to
   `var/sweep/<basename>/pc-<value>/<basename>.pha`. Use the same
   string-formatted pc value (`(format nil "~F" pc)` — same `~F` we already
   use in `materialize-template`, so the row's pc text matches the dir name).

2. **`:directory` kwarg on phaverlite spawn.** The existing
   `(uiop:launch-program (list "phaverlite" out-path) :output :stream
   :error-output :output)` gains `:directory pc-dir`. phaverlite's
   side-effect files (`out_reach`, `out_inv`) land in pc-dir as a result.

3. **`template-basename` slot in `sweep-state`** — captures the basename
   string at `run-sweep` time. Used by `phaverlite-sweep-plot-row` to
   locate `var/sweep/<basename>/`. Stash on a buffer-local var of
   `*phaverlite-sweep*` when the buffer is created, so the `p` handler
   doesn't depend on `*active-sweep*` (which is cleared when the sweep
   finishes).

4. **`p` keybind on `*phaverlite-sweep*`'s buffer-local keymap.** The
   existing `*phaverlite-mode-keymap*` is for `.pha` source buffers (`C-c
   C-s`/`C-c C-n`/`C-c C-k`). The sweep results buffer is NOT in
   phaverlite-mode, so it needs its own keymap. Set it up via
   `lem:make-keymap :name '*phaverlite-sweep-buffer-keymap*` at the bottom
   of `src/sweep.lisp` and apply with
   `(setf (lem:buffer-keymap buf) *phaverlite-sweep-buffer-keymap*)` in
   `ensure-sweep-buffer`. Bind `p` →
   `phaverlite-mode/plot:phaverlite-sweep-plot-row` after both files load.

   (If lem doesn't expose `buffer-keymap` as a setter, fallback: bind
   `p` globally on `*phaverlite-mode-keymap*` and have the command
   no-op-with-message when not in `*phaverlite-sweep*`. Less clean but
   functional. Pick at implementation time after grepping `.lem-ref/`.)

## Data flow

**Single-run plot:**
```
user opens bouncing_ball.pha
user types C-c C-p
  → phaverlite-plot-buffer
  → preconditions (file? not in sweep? modified+y?)
  → plot-dir = var/plot/bouncing_ball/   (ensure dirs)
  → uiop:launch-program ("phaverlite" path)
        :output :stream :error-output :output
        :directory plot-dir
    (synchronous wait; stdout discarded)
  → (render-plot-dir plot-dir)
        check out_reach + out_inv exist
        graph -T png … > plot-dir/plot.png
        open plot-dir/plot.png  (async)
        lem:message "Plot: <path>"
```

**Sweep-row plot:**
```
sweep finished or in-progress; *phaverlite-sweep* has rows
user moves point onto a row
user presses p
  → phaverlite-sweep-plot-row
  → check current buffer is *phaverlite-sweep*
  → parse pc from line at point
  → derive var/sweep/<basename>/pc-<pc>/
  → probe-file → exists?
  → (render-plot-dir per-pc-dir)
```

**Sweep engine (per-pc dir flow, after touch-up):**
```
inside sweep-tick, when spawning next pc value:
  pc-dir = var/sweep/<basename>/pc-<formatted-pc>/
  ensure-directories-exist pc-dir
  out-path = pc-dir/<basename>.pha
  materialize-template template-path out-path pc
  uiop:launch-program ("phaverlite" out-path)
    :output :stream :error-output :output
    :directory pc-dir
```

## Error handling

| Where | Failure | Policy |
|---|---|---|
| `phaverlite-plot-buffer`, no filename | — | Message `Buffer not visiting a file`; abort |
| Buffer modified, user answers `n` | — | Silent abort |
| `*active-sweep*` non-nil during plot-buffer | Concurrent phaverlite spawns | Refuse: `Sweep in progress; use 'p' on a sweep row instead` |
| `phaverlite` not on PATH | `uiop:launch-program` raises | Catch; message `phaverlite: command not found on PATH`; abort, no render |
| `phaverlite` exits non-zero | Process completes non-zero | Continue to render anyway — out_reach/out_inv may exist; render-plot-dir handles missing files |
| `out_reach` or `out_inv` missing in plot-dir | render-plot-dir precondition fails | Message `Plot: no out_reach/out_inv in <dir> (did your .pha use .print?)`; return NIL |
| `graph` not on PATH | `uiop:run-program` raises | Catch; message `graph: command not found (install GNU plotutils)`; abort |
| `graph` exits non-zero | Process completes non-zero | Catch; message `graph failed: <stderr first line>`; partial PNG (if any) stays on disk; no `open` |
| `open` fails (e.g., headless session) | `uiop:launch-program` raises | Catch; message `open failed: <err>; plot at <path>`. PNG was rendered successfully; user opens manually |
| `phaverlite-sweep-plot-row` outside `*phaverlite-sweep*` | Wrong buffer | Message `Not in a *phaverlite-sweep* buffer`; return |
| Cursor not on a result row | First token doesn't parse as float | Message `No sweep row at point`; return |
| Per-pc dir missing (e.g., row was cancelled) | `probe-file` returns NIL | Message `No plot data for pc=<pc> (was it cancelled?)`; return |
| Concurrent plot requests | Race on `plot.png` | Acceptable for prototype — `graph` rewrites in place; brief stale view in Preview at worst |

No retry. No fallback. No automatic re-run. Failures messaged via
`lem:message` (which is also recorded in lem's built-in `*Messages*`
buffer); user decides next step.

## Testing

Same single-file rove suite (`tests/main.lisp`). Runner unchanged in
spirit; `bin/test-mode` extended with two `ln -sf` lines for the new fakes.

### `tests/fake-graph` (new shell stub)

```sh
#!/bin/sh
# tests/fake-graph — stand-in for GNU plotutils `graph(1)`.
# Tests pass the output redirection at the lisp side via uiop's :output
# :stream + an open file, so we just dump a marker to stdout.
echo "FAKE GRAPH OUTPUT"
exit "${FAKE_EXIT:-0}"
```

### `bin/test-mode` extension

One line added next to the existing `phaverlite` symlink:
```sh
ln -sf "$REPO/tests/fake-graph" "$REPO/var/test-bin/graph"
```

The async `open` call in `render-plot-dir` is wrapped in `handler-case`;
under a headless `--script` rove run it'll likely fail (no GUI session)
and the failure is silently swallowed — that's the documented behavior
("open failed: <err>; plot at <path>"). Tests don't need to assert on
`open` invocation.

### New deftests

- **`(deftest plot-render …)`** — pure exercise of `render-plot-dir`:
  - Both files present: create temp dir, write minimal `out_reach` +
    `out_inv` (`"1 2 0~%3 4 0"`), call render, assert `dir/plot.png`
    exists and contains the FAKE GRAPH OUTPUT marker.
  - `out_reach` missing: stub `lem:message` (let-bind via `fdefinition`
    swap, like sub-project B's `with-stubbed-prompt`); call render;
    assert message contains `no out_reach/out_inv`; assert no `plot.png`.
  - `out_inv` missing: same pattern.
- **`(deftest plot-buffer-command …)`** — end-to-end with fake binaries:
  - Create temp `.pha` (any content; fake-phaverlite ignores it). Stub
    prompt → `:yes`. Invoke `phaverlite-plot-buffer`. Assert
    `var/plot/<basename>/plot.png` exists. (Will only exist if
    fake-phaverlite "produces" out_reach/out_inv — our existing
    fake-phaverlite doesn't, so the test will need to write those files
    itself before invoking the command, OR we extend fake-phaverlite to
    `touch out_reach out_inv` in plot mode. Decision: extend.
    `FAKE_PHAVERLITE_MODE=plot` causes the fake to `touch` those files
    in cwd before exiting. Existing run-buffer + sweep modes preserved.)
  - Refuse-when-sweep-in-progress: set `*active-sweep*` to a dummy
    struct, invoke command, assert message contains `Sweep in progress`,
    assert no plot dir created.
- **`(deftest sweep-plot-row …)`** — end-to-end with the touched-up
  sweep + fake graph:
  - Run a 2-value sweep with `FAKE_PHAVERLITE_MODE=sweep` AND
    `FAKE_TOUCH_REACH_INV=1` (extend fake again — when this var is set,
    the sweep mode also touches `out_reach` + `out_inv` in cwd, mimicking
    a real phaverlite that emits both stdout reachability text AND
    side-effect files). Wait for completion. Assert
    `var/sweep/<basename>/pc-3.0/` and `pc-2.0/` dirs exist with
    `out_reach`, `out_inv`, and the materialized `.pha` inside.
  - Switch to `*phaverlite-sweep*`, move point to first row, invoke
    `phaverlite-sweep-plot-row`. Assert
    `var/sweep/<basename>/pc-3.0/plot.png` exists.
  - Wrong-buffer: switch to a different buffer, invoke command, assert
    message contains `Not in a *phaverlite-sweep* buffer`.

### `sweep-engine` deftest update

Add one assertion verifying per-pc dirs were created with the
materialized `.pha` inside:
```lisp
(testing "per-pc dirs are created with materialized .pha"
  (ok (probe-file "var/sweep/<basename>/pc-3.0/<basename>.pha"))
  (ok (probe-file "var/sweep/<basename>/pc-2.0/<basename>.pha")))
```
(Replace `<basename>` with whatever `make-temp-pha-template` produces.)

If any existing assertion in `sweep-engine` checks the materialized path
literally, update it to the new layout. Most assertions are on buffer
content (the `*phaverlite-sweep*` text), which is unaffected.

### Pass criteria for D

- `bin/test-mode` exits 0 with all sub-project B/C oks intact (with
  touch-up update applied) plus new D oks.
- Smoke (Step A): open `Lab3/bouncing_ball.pha`, `C-c C-p`, see
  Preview.app pop with a plot.
- Smoke (Step B): open `Lab3/heater_template.pha`, `C-c C-s` → accept
  default range, wait for sweep to complete; move point onto a result
  row, press `p`, see Preview.app pop with that pc's reach-set.
- Smoke (Step C): `bin/verify-isolation` PASS.

## Files added

```
src/plot.lisp                                                     new
tests/fake-graph                                                  new (executable)
docs/superpowers/specs/2026-05-09-sub-project-d-design.md         (this file)
```

## Files modified

```
phaverlite-mode.asd        +1 component: (:file "plot")
src/sweep.lisp             per-pc subdirs, :directory kwarg on launch-program,
                            template-basename slot, p keybind on
                            *phaverlite-sweep* buffer-local keymap
src/commands.lisp          unchanged (the C-c C-p binding goes in
                            src/plot.lisp's bottom — same load-order
                            pattern as sub-project C's bindings)
tests/main.lisp            +3 deftests, +1 assertion in sweep-engine
tests/fake-phaverlite      add FAKE_PHAVERLITE_MODE=plot branch (touch
                            out_reach + out_inv in cwd) AND a
                            FAKE_TOUCH_REACH_INV env-var hook for the
                            sweep mode (also touches in cwd)
bin/test-mode              +1 ln -sf line for fake-graph
```

## After D

`bin/build-image` rebuilds `var/lem.core` to bake `phaverlite-mode/plot`
into the image. Day-to-day launches stay sub-second. Opening any `.pha`
file gives the full toolset:

- `C-c C-c` — run phaverlite, dump stdout to `*phaverlite-output*` (B)
- `C-c C-s` — sweep, fill `*phaverlite-sweep*` row by row (C)
- `C-c C-n` / `C-c C-k` — skip / kill sweep (C)
- `C-c C-p` — plot the current `.pha` (D)
- `p` on a sweep row — plot that row's reach-set (D)

Sub-project E (`phaverlite-lsp`) is the last unit: project-local LSP for
parse-error diagnostics, document symbols (automata, locations), keyword
hover. Likely a separate ASDF system at that point — the LSP server has
its own deps (jsonrpc, etc., already in qlfile from sub-project A) and
is a meaningfully larger surface than B+C+D combined.
