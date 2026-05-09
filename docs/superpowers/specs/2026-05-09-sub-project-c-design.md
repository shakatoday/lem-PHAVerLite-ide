# Sub-project C — `pc-sweep` (interactive PC sweep UI)

**Date:** 2026-05-09
**Status:** Approved design, not yet implemented
**Scope:** Third of five sub-projects. Builds on sub-projects A and B. See
`CLAUDE.md` for the A→B→(C,D,E) decomposition.

## Goal

Replace `Lab3/sweep_pc.sh` with an in-editor command. From a `.pha` template
buffer (must contain `__PC__`), the user runs `M-x phaverlite-sweep-buffer`
(also `C-c C-s`), enters a range as `start step stop` in the minibuffer, and
watches a results buffer fill in row-by-row as `phaverlite` runs the sweep
sequentially. The user can skip a slow value (`C-c C-n`) or kill the whole
sweep (`C-c C-k`) at any time.

After C, the IDE exposes the full sweep workflow without ever shelling out to
`sweep_pc.sh`. Plot generation (D) and LSP (E) remain out of scope.

## Definition of done

1. `M-x phaverlite-sweep-buffer` (or `C-c C-s`) on a `.pha` buffer:
   - Refuses with `Buffer not visiting a file` if the buffer has no filename.
   - Refuses with `No __PC__ placeholder in <file>` if the file lacks the
     literal placeholder.
   - Refuses with `Sweep already in progress (use C-c C-k to cancel)` if
     `*active-sweep*` is non-nil.
   - If buffer modified, prompts y/n to save (same prompt shape as
     `phaverlite-run-buffer`).
   - Prompts `Sweep PC (start step stop): ` with the previous run's three
     values pre-filled (or `3.0 -0.05 1.0` on first invocation).
   - Range validation: re-prompts on parse error or zero/sign-mismatched step.
2. `*phaverlite-sweep*` buffer opens in a horizontal split below the source.
   Cursor stays in source.
3. Buffer layout (matches the approved mockup):
   ```
   $ phaverlite-sweep heater_template.pha
   Sweep PC: start=3.0  step=-0.05  stop=1.0  (41 values)
   [8/41 done]  current: pc=2.65

   pc       result          cpu(s)
   -------- --------------- ----------
   3.00     unreachable     0.42
   2.95     unreachable     0.41
   ...
   2.65     ...running...
   ```
   Header (line 1-2) is immutable. Status line (line 3) is rewritten in place
   per iteration. Rows below the table separator append as each `phaverlite`
   exits.
4. `C-c C-n` (`phaverlite-sweep-skip`): SIGTERMs the in-flight `phaverlite`,
   marks the row `(cancelled)` `--`, advances to the next pc value.
5. `C-c C-k` (`phaverlite-sweep-cancel`): SIGTERMs the in-flight `phaverlite`,
   stops the loop, rewrites status line as `[N/total done]  cancelled by user`.
6. Result row format reproduces `Lab3/sweep_pc.sh`'s contract (CLAUDE.md):
   - `pc` (column-aligned, 8 wide)
   - `result` ∈ `{reachable, unreachable, ?, error(<exit>), cancelled}`
     (15 wide)
   - `cpu(s)` (penultimate field of last `Time in get_reach_set` line, or
     `--`) (10 wide)
7. Materialized template lives at `var/sweep/<basename>.pha`, **overwritten
   per iteration** (matches `sweep_pc.sh`'s single `/tmp/heater_run.pha`
   pattern but under repo's gitignored `var/`).
8. `bin/test-mode` exits 0 with sub-project B's 22 oks plus the new sweep
   deftests.
9. `bin/verify-isolation` PASS (no new `$HOME` writes from sweep code).

**Out of scope for C:**
- Plot generation (sub-project D)
- LSP diagnostics / symbols / hover (sub-project E)
- Multiple parameters / N-D grid sweeps (single `__PC__` only — see
  brainstorming Q1)
- Configurable placeholder name (always `__PC__`)
- Per-value timeout (cancellation is the user's escape hatch)
- Replay from results buffer (re-trigger from source)
- Persisted sweep history beyond `*last-sweep-args*` for prefill
- Parallel `phaverlite` runs (always sequential — matches the script and
  avoids resource contention)
- C-g hijacking — C-g keeps its universal lem semantics; sweep skip and
  cancel are explicit chords

## Architecture

Folded into the existing `phaverlite-mode` ASDF system. No new system. One
new source file, one new package, tests added to the existing single-file
rove suite. Justification: project still small enough that a separate system
would create package boundaries that don't earn their keep; we'll split when
sweep grows past ~300 lines or one of its responsibilities (parse / render /
engine / commands) starts dominating.

```
src/sweep.lisp                package phaverlite-mode/sweep
                              -- everything: range gen, template substitution,
                                 phaverlite-stdout parsing, results-buffer
                                 rendering, sequential spawn + cancellation,
                                 interactive commands.
                              Exports: phaverlite-sweep-buffer,
                                       phaverlite-sweep-skip,
                                       phaverlite-sweep-cancel
phaverlite-mode.asd           +1 component: (:file "sweep") at the end
src/commands.lisp             +2 lines at the bottom binding C-c C-s,
                              C-c C-n, C-c C-k in *phaverlite-mode-keymap*
                              to the sweep commands
tests/main.lisp               +deftests: sweep-parse, sweep-range,
                              sweep-render, sweep-engine
tests/fake-phaverlite         extended with FAKE_PHAVERLITE_MODE=sweep
                              behavior: emit phaverlite-shaped output
                              (see "Testing")
```

`config/init.lisp` and `bin/build-image` are untouched — they already load
`phaverlite-mode`, and adding a component to its asd is enough. Image
rebuild via `bin/build-image` is required after to bake `phaverlite-mode/sweep`
into `var/lem.core`.

## Components (top-to-bottom inside `src/sweep.lisp`)

### Module-private state

```lisp
(defvar *active-sweep* nil
  "SWEEP-STATE struct describing the in-flight sweep, or NIL when idle.
   Mutated only by the engine and the skip/cancel commands.")

(defstruct sweep-state
  template-path                     ; pathname of the source .pha
  output-path                       ; var/sweep/<basename>.pha (overwritten)
  values                            ; list of remaining pc values (floats)
  total                             ; original count, for status line
  done                              ; count of completed values
  current-pc                        ; the value currently running, or NIL
  current-process                   ; uiop process-info, or NIL
  cancel-flag)                      ; :skip, :kill, or NIL

(defparameter *last-sweep-args* nil
  "List (start step stop) from the last successful sweep — used to prefill
   the next minibuffer prompt. NIL means use the default 3.0 -0.05 1.0.")
```

### Range generation

`(generate-range start step stop) → list of floats`. Mirrors `seq` semantics.
Inclusive of `stop` when reachable. Validates step ≠ 0 and that
`(- stop start)` and `step` share a sign. Errors are caught by the command's
input parser and surface as a re-prompt.

### Template substitution

`(materialize-template template-path output-path pc) → output-path`. Reads
the source `.pha`, substitutes `__PC__` → `(princ-to-string pc)`, writes
`output-path`. Errors if the template doesn't contain `__PC__` (which the
command should have already checked, but defense-in-depth).

### Phaverlite stdout parser

```lisp
(parse-result stdout-string) → :reachable | :unreachable | :unknown
(parse-cpu-time stdout-string) → string | NIL
```

`parse-result`: greps the entire stdout. We check the substring
`not reachable` **before** `is reachable` — matches `sweep_pc.sh`'s
precedence: an output containing both phrases yields `:unreachable`. We
deliberately do NOT match a hardcoded region name (the script's literal
`bad`); phaverlite emits `<region-name> not reachable` / `<region-name> is
reachable` where the name is whatever the user's `.pha` assigned. The
substring `not reachable` (and `is reachable`) is unique enough on its own
in phaverlite output. (In practice phaverlite only emits one or the other
per check; the precedence only matters as a defensive tie-break.)

`parse-cpu-time`: finds the LAST `Time in get_reach_set` line, splits on
whitespace, returns the penultimate field. NIL if no such line.

### Results-buffer renderer

```lisp
(ensure-sweep-buffer) → buffer       ; *phaverlite-sweep*, get-or-create
(write-header buf template-path start step stop count)
(write-status-line buf done total current-pc-or-cancelled)
(write-row buf pc result-symbol cpu-string)
(finalize buf done total cancelled-p)
```

Header (lines 1-2) written once per sweep, immutable thereafter.
Status line (line 3) re-written in place per iteration: erase line 3,
insert new contents. Rows append below the `--------` separator.
On cancel/kill, `finalize` rewrites the status line to a final summary
(e.g. `[8/41 done]  cancelled by user` or `[41/41 done]  finished`).

### Sweep engine

```lisp
(run-sweep template-path start step stop) → sweep-state
```

Builds the `sweep-state`, sets `*active-sweep*`, materializes the buffer
and writes the header + initial status line, then schedules the first
iteration via lem's timer (`lem:start-timer` with a 0ms initial delay).

Each tick:
1. Read `cancel-flag`. `:kill` → finalize and clear `*active-sweep*`.
   `:skip` → if `current-process` running, `uiop:terminate-process`; append
   `(cancelled)` row; clear flag; fall through.
2. If `values` empty → finalize and clear `*active-sweep*`.
3. Pop next pc, materialize template, update status line.
4. Spawn `phaverlite` via `uiop:launch-program (list "phaverlite" path)
   :output :stream :error-output :output`. Store as `current-process`.
5. Schedule a follow-up tick that checks for process completion. When
   complete: read stdout, parse, write row, increment `done`, clear
   `current-process`, schedule the next iteration.

Sequential by design — at most one `phaverlite` alive at a time.

### Interactive commands

```lisp
(define-command phaverlite-sweep-buffer () ()
  ;; Refuse if *active-sweep* non-nil. Validate filename + __PC__ presence.
  ;; If modified, prompt save y/n. Prompt range with prefill. Parse + validate.
  ;; Update *last-sweep-args*; (run-sweep …).
  )

(define-command phaverlite-sweep-skip () ()
  ;; If *active-sweep* nil: message "No phaverlite-sweep in progress".
  ;; Else (setf (sweep-state-cancel-flag *active-sweep*) :skip).
  )

(define-command phaverlite-sweep-cancel () ()
  ;; If *active-sweep* nil: message "No phaverlite-sweep in progress".
  ;; Else (setf (sweep-state-cancel-flag *active-sweep*) :kill).
  )
```

Exports: just the three commands. Everything else internal to the package.

## Data flow

**Sweep startup:**

```
user opens heater_template.pha (any .pha buffer)
user types C-c C-s
  → phaverlite-sweep-buffer
  → check *active-sweep* nil
  → check buffer-filename non-nil + file contains "__PC__"
  → if buffer modified: prompt y/n → save (or abort on n)
  → prompt "Sweep PC (start step stop): " prefilled
  → parse 3 floats; on parse error re-prompt with same input visible
  → update *last-sweep-args*
  → run-sweep:
      build sweep-state with values = generate-range(start step stop)
      set *active-sweep*
      ensure-sweep-buffer; pop-to-buffer (horizontal split below source)
      write-header + write-status-line "[0/N done]  starting…"
      lem:start-timer with 0ms → first iteration tick
  → cursor stays in source buffer
```

**Per-iteration tick:**

```
case (sweep-state-cancel-flag state) of
  :kill → finalize(buf, done, total, cancelled-p=t)
          clear *active-sweep*; return
  :skip → if current-process: uiop:terminate-process
          write-row(current-pc, :cancelled, "--")
          clear cancel-flag; fall through
  nil   → fall through

if (values state) empty:
  finalize(buf, done, total, cancelled-p=nil)
  clear *active-sweep*; return

pop next pc; set current-pc
materialize-template → var/sweep/<basename>.pha
write-status-line "[done/total done]  current: pc=<pc>"
spawn phaverlite via uiop:launch-program
store as current-process
schedule completion-poll tick (every ~50ms via lem:start-timer)
  on completion:
    read stdout to string
    parse-result + parse-cpu-time
    write-row(pc, result, cpu)
    increment done; clear current-process
    schedule next iteration tick
```

**Skip / cancel:**

```
user types C-c C-n  →  phaverlite-sweep-skip
                   →  if *active-sweep* nil: message "No sweep in progress"
                   →  else set cancel-flag = :skip
                       (engine picks it up at next tick boundary, which is
                        within ~50ms; if mid-process, the engine kills it
                        before advancing)

user types C-c C-k  →  phaverlite-sweep-cancel  → same shape, sets :kill
```

**Finalization:**

Status line gets rewritten to summary form:
- normal: `[41/41 done]  finished`
- killed: `[8/41 done]  cancelled by user`

`*phaverlite-sweep*` becomes read-only (`(setf (buffer-read-only-p buf) t)`).
Source buffer remains focused throughout.

## Error handling

| Where | Failure | Policy |
|---|---|---|
| Buffer not visiting a file | No filename | Message `Buffer not visiting a file`; abort |
| File missing `__PC__` | Precondition fails | Message `No __PC__ placeholder in <file>`; abort |
| Buffer modified, user answers `n` | — | Silent abort |
| `*active-sweep*` non-nil | Concurrent sweep | Message `Sweep already in progress (use C-c C-k to cancel)` |
| Range parse error | `parse-float` raises | Re-prompt, input pre-filled, footer shows `Bad input: …` |
| Range validation: step=0 or sign mismatch | `generate-range` raises | Re-prompt with `Bad range: step direction doesn't reach stop` |
| `phaverlite` not on PATH | `uiop:launch-program` raises | Catch in engine: write row `pc | error | --`; finalize early with summary `aborted: phaverlite not on PATH`; clear `*active-sweep*` |
| Single `phaverlite` exits non-zero | Process completes with non-zero | Treat as success-of-the-loop: write row `pc | error(<exit>) | --`; continue to next pc |
| Output has neither reachable phrase | — | Row gets `?` (matches `sweep_pc.sh`); cpu still attempted |
| No `Time in get_reach_set` line | — | Cpu = `--` |
| `materialize-template` write fails | I/O error | Catch, message `Cannot write <path>: <err>`; finalize early; clear state |
| Skip/cancel command, no sweep running | — | Message `No phaverlite-sweep in progress`; no-op |
| User kills `*phaverlite-sweep*` buffer mid-sweep with `C-x k` | Buffer gone | Engine's next render call detects buffer dead → finalize cleanly, clear `*active-sweep*` |
| `phaverlite` hangs forever on a value | No timeout in spec | Out of scope. User uses `C-c C-n` or `C-c C-k`. The "non-optimal pc explodes time" risk is exactly what these keys are for |

No retry. No fallback. No automatic re-run. Failures are visible in the
row table; user decides what to do.

## Testing

Same single-file rove suite (`tests/main.lisp`), extending the existing
`phaverlite-mode-tests` system. `bin/test-mode` runner is unchanged.

### New deftests

- **`(deftest sweep-parse …)`** — pure tests against canned phaverlite
  stdout fixtures. Cases: `bad is reachable` → `:reachable`; `bad not
  reachable` → `:unreachable`; **`target is reachable`** (different
  region name) → `:reachable`; **`unsafe not reachable`** → `:unreachable`;
  neither phrase → `:unknown`; cpu = penultimate field of last
  `Time in get_reach_set` line; cpu = NIL when no such line.
- **`(deftest sweep-range …)`** — pure tests on `generate-range`.
  Cases: `(3.0 -0.05 1.0)` → 41 values starting 3.0 ending 1.0;
  `(1.0 0.5 3.0)` → 5 values; `start=stop` → one value; `step=0` raises;
  sign-mismatched step raises.
- **`(deftest sweep-render …)`** — exercise the renderer against a fresh
  buffer. Cases: `write-header` produces the expected first three lines;
  `write-row` appends a column-aligned line matching the layout preview;
  `write-status-line` rewrites in place (call twice, only one status line
  exists); `finalize` rewrites status line to summary form.
- **`(deftest sweep-engine …)`** — end-to-end with the extended
  `tests/fake-phaverlite`. Cases: 3-value sweep produces 3 rows + finished
  summary + clears `*active-sweep*`; skip case marks one row `(cancelled)`,
  sweep continues, finishes; kill case stops at current value, summary
  reads `cancelled by user`, no further rows.

### `tests/fake-phaverlite` extension

The existing fake binary (from sub-project B) gets a sweep mode driven by
env vars. When invoked with `FAKE_PHAVERLITE_MODE=sweep`, it emits
phaverlite-shaped output the parser recognizes; otherwise it behaves as
today (echo + exit). Pseudo-shell:

```sh
case "${FAKE_PHAVERLITE_MODE:-}" in
  sweep)
    case "${FAKE_RESULT:-unreachable}" in
      reachable)   echo "bad is reachable" ;;
      unreachable) echo "bad not reachable" ;;
      *)           echo "(no result)" ;;
    esac
    echo "Time in get_reach_set : ${FAKE_CPU:-0.42} s"
    [ -n "${FAKE_SLEEP:-}" ] && [ "${FAKE_SLEEP}" -gt 0 ] && sleep "$FAKE_SLEEP"
    exit "${FAKE_EXIT:-0}"
    ;;
  *)
    echo "FAKE OUTPUT $1"
    exit "${FAKE_EXIT:-0}"
    ;;
esac
```

One binary, two modes. `bin/test-mode` already symlinks it as `phaverlite`
on PATH; sweep deftests `let`-bind env vars per call.

### Pass criteria for C

- `bin/test-mode` exits 0 (B's existing 22 oks plus C's new sweep oks,
  estimated ~20 → ~42 total).
- Smoke test: open `Lab3/heater_template.pha`, type `C-c C-s`, accept the
  default range `3.0 -0.05 1.0`, watch the `*phaverlite-sweep*` buffer
  fill in row by row, see final summary `[41/41 done]  finished`.
- `bin/verify-isolation` PASS.

## Files added

```
src/sweep.lisp                                                    new
docs/superpowers/specs/2026-05-09-sub-project-c-design.md         (this file)
```

## Files modified

```
phaverlite-mode.asd        +1 component: (:file "sweep")
src/commands.lisp          +3 define-key forms (C-c C-s, C-c C-n, C-c C-k)
tests/main.lisp            +4 deftests (sweep-parse, sweep-range,
                                        sweep-render, sweep-engine)
tests/fake-phaverlite      +sweep-mode branch driven by env vars
```

## After C

`bin/build-image` rebuilds `var/lem.core` to bake `phaverlite-mode/sweep`
into the image. After that, day-to-day launches stay sub-second; opening a
`.pha` file gives the run-buffer (`C-c C-c`) AND sweep (`C-c C-s`) commands
out of the box.

Sub-project D (`plot`) lands `plotutils` integration: render the
reachability vertices in `out_reach` / invariant grid in `out_inv` to a
PNG/SVG and pop it into a side buffer. Likely a sibling file `src/plot.lisp`
and a couple of commands hung off the sweep results buffer (e.g.
`p` on a row plots that pc value's reach set).
