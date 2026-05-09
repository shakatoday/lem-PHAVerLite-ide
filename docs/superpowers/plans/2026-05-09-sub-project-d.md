# Sub-project D — plot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render PHAVerLite's reach-set / invariant output (`out_reach`, `out_inv`) to a PNG via GNU plotutils `graph(1)`, opened in the system viewer (`open` on macOS). Two surfaces: `M-x phaverlite-plot-buffer` (`C-c C-p`) for standalone .pha plotting, and `p` on a row in `*phaverlite-sweep*` for per-pc plotting.

**Architecture:** One new source file `src/plot.lisp` (package `phaverlite-mode/plot`) added as the last component of `phaverlite-mode.asd`. Plus a small touch-up to `src/sweep.lisp`: per-pc subdirs, `:directory` kwarg on phaverlite spawn, `template-basename` slot on sweep-state, and a thin `phaverlite-sweep-results-mode` major mode that scopes the `p` keybind to the `*phaverlite-sweep*` buffer.

**Tech Stack:** SBCL + lem (pinned in `qlfile`) + qlot for deps + rove for tests + `uiop:launch-program` (async spawn / open) + `uiop:run-program` (graph invocation) + zsh launcher.

**Spec:** `docs/superpowers/specs/2026-05-09-sub-project-d-design.md` — read it first.

**Key references in `.lem-ref/`:**
- `.lem-ref/extensions/dot-mode/dot-mode.lisp` — minimal `define-major-mode` example (used in B too).
- `.lem-ref/src/system.lisp:34` — lem's own `(uiop:launch-program (list "open" (namestring pathname)))` for opening files on macOS.
- `.lem-ref/src/system.lisp:26` — `uiop:run-program` pattern.
- `src/sweep.lisp` (this repo, sub-project C) — engine pattern to extend.
- `src/commands.lisp` (this repo, sub-project B) — buffer-modified prompt + spawn pattern to model the plot command after.

---

## File structure

| File | Action | Purpose |
|---|---|---|
| `src/plot.lisp` | create | New file. Package `phaverlite-mode/plot`. Holds `render-plot-dir` primitive, `phaverlite-plot-buffer` and `phaverlite-sweep-plot-row` commands, the `C-c C-p` define-key. |
| `phaverlite-mode.asd` | modify | Add `(:file "plot")` as the last component, after `(:file "sweep")`. |
| `src/sweep.lisp` | modify | (1) Per-pc subdirs (`var/sweep/<basename>/pc-<value>/`), (2) `:directory pc-dir` on phaverlite spawn, (3) new `template-basename` slot on `sweep-state` + buffer-local stash, (4) `phaverlite-sweep-results-mode` major mode + `p` keybind, applied in `ensure-sweep-buffer`. |
| `tests/main.lisp` | modify | +3 deftests: `plot-render`, `plot-buffer-command`, `sweep-plot-row`. Update `sweep-engine` deftest with per-pc dir assertion. |
| `tests/fake-phaverlite` | modify | Extend with `FAKE_PHAVERLITE_MODE=plot` mode (touches `out_reach`/`out_inv` in cwd). Extend `sweep` mode with `FAKE_TOUCH_REACH_INV` env hook to also touch them. |
| `tests/fake-graph` | create (executable) | Stand-in for `graph(1)`: echoes `FAKE GRAPH OUTPUT`, exits `${FAKE_EXIT:-0}`. |
| `tests/fake-open` | create (executable) | Stand-in for macOS `open(1)`: echoes `FAKE OPEN $1`, exits 0. |
| `bin/test-mode` | modify | Add two `ln -sf` lines for `fake-graph` and `fake-open` next to the existing `phaverlite` symlink. |
| `var/plot/` | runtime | Created by plot command. Gitignored (under `var/*`). |
| `var/sweep/<basename>/pc-<v>/` | runtime | Created by touched-up sweep engine. Gitignored. |
| `var/lem.core` | regenerated | Rebuild via `bin/build-image` after wiring (no script change needed — phaverlite-mode.asd already covers the new component). |

---

## Task 1: Skeleton — empty `src/plot.lisp` + asd component, verify load

**Files:**
- Create: `src/plot.lisp`
- Modify: `phaverlite-mode.asd`

- [ ] **Step 1: Create `src/plot.lisp` with package shell**

```lisp
;;;; src/plot.lisp — plotutils integration for PHAVerLite reach-set /
;;;; invariant output.
;;;;
;;;; Two interactive surfaces:
;;;;   M-x phaverlite-plot-buffer       (C-c C-p)  — standalone .pha plot
;;;;   M-x phaverlite-sweep-plot-row    (`p` in *phaverlite-sweep*)
;;;; Both share a single primitive: render-plot-dir.
;;;; See docs/superpowers/specs/2026-05-09-sub-project-d-design.md.

(defpackage #:phaverlite-mode/plot
  (:use #:cl #:lem)
  (:export #:phaverlite-plot-buffer
           #:phaverlite-sweep-plot-row))
(in-package #:phaverlite-mode/plot)
```

- [ ] **Step 2: Add `(:file "plot")` as the last component in `phaverlite-mode.asd`**

The current asd lists `(:file "syntax")`, `(:file "indent")`, `(:file "commands")`, `(:file "mode")`, `(:file "sweep")`. Append `(:file "plot")` at the end:

```lisp
(defsystem "phaverlite-mode"
  :description "PHAVer (.pha) major mode for lem."
  :depends-on ("lem/core")
  :pathname "src"
  :serial t
  :components ((:file "syntax")
               (:file "indent")
               (:file "commands")
               (:file "mode")
               (:file "sweep")
               (:file "plot")))
```

- [ ] **Step 3: Verify the system loads**

```bash
PHAVERLITE_IDE_LIB="$PWD/var/lib" qlot exec sbcl \
  --noinform --no-userinit --no-sysinit \
  --eval '(ql:quickload :cffi :silent t)' \
  --eval '(let ((d (uiop:getenv "PHAVERLITE_IDE_LIB"))) (when d (pushnew (uiop:ensure-directory-pathname d) cffi:*foreign-library-directories* :test #'\''equal)))' \
  --eval '(pushnew (truename ".") asdf:*central-registry* :test #'\''equal)' \
  --eval '(ql:quickload :phaverlite-mode :silent t)' \
  --eval '(format t "loaded: ~a~%" (find-package :phaverlite-mode/plot))' \
  --eval '(uiop:quit 0)'
```

Expected: `loaded: #<PACKAGE "PHAVERLITE-MODE/PLOT">` and exit 0.

- [ ] **Step 4: Verify the existing test suite still passes**

```bash
bin/test-mode 2>&1 | tail -3
```

Expected: `All 1 test passed.` Sub-project B + C oks all green.

- [ ] **Step 5: Commit**

```bash
git add src/plot.lisp phaverlite-mode.asd
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project D: skeleton — empty plot.lisp + asd component

Adds src/plot.lisp (package phaverlite-mode/plot) as the last component
of phaverlite-mode.asd. No behavior yet — just the package shell.
Verifies the existing test suite still green.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Extend `tests/fake-phaverlite` with plot mode + touch hook for sweep

**Files:**
- Modify: `tests/fake-phaverlite`

The fake binary already supports default mode and `FAKE_PHAVERLITE_MODE=sweep`. Plot tests need:

1. A `plot` mode that touches `out_reach` and `out_inv` in cwd (so `render-plot-dir` finds them).
2. An optional `FAKE_TOUCH_REACH_INV` env var that makes the existing `sweep` mode ALSO touch those files (so `sweep-plot-row` deftests find them in per-pc dirs).

- [ ] **Step 1: Read the current fake binary**

```bash
cat tests/fake-phaverlite
```

Confirm: it has a `case "${FAKE_PHAVERLITE_MODE:-}" in sweep) ... ;; *) ... ;; esac` structure.

- [ ] **Step 2: Replace with the three-mode version**

```bash
cat > tests/fake-phaverlite <<'EOF'
#!/bin/sh
# tests/fake-phaverlite — test fixture for phaverlite invocations.
#
# Three modes:
#
#   1. Default (no FAKE_PHAVERLITE_MODE): echoes "FAKE OUTPUT $1" and
#      exits $FAKE_EXIT (default 0). Used by sub-project B's
#      phaverlite-run-buffer tests.
#
#   2. FAKE_PHAVERLITE_MODE=sweep: emits phaverlite-shaped output the
#      pc-sweep parser recognizes. Driven by env vars:
#         FAKE_RESULT  reachable | unreachable | unknown   (default unreachable)
#         FAKE_CPU     <seconds>                            (default 0.42)
#         FAKE_SLEEP   <seconds>                            (default 0)
#         FAKE_EXIT    <code>                               (default 0)
#         FAKE_TOUCH_REACH_INV  any non-empty value         (default unset)
#           If set, also `touch out_reach out_inv` in cwd so the sweep
#           plot-row deftest finds them in the per-pc dir.
#
#   3. FAKE_PHAVERLITE_MODE=plot: touches out_reach and out_inv in cwd
#      (mimicking real phaverlite's .print() side effects), exits
#      $FAKE_EXIT (default 0). No stdout text needed — the plot command
#      doesn't parse stdout.

case "${FAKE_PHAVERLITE_MODE:-}" in
  sweep)
    case "${FAKE_RESULT:-unreachable}" in
      reachable)   echo "bad is reachable" ;;
      unreachable) echo "bad not reachable" ;;
      *)           echo "(no result)" ;;
    esac
    echo "Time in get_reach_set : ${FAKE_CPU:-0.42} s"
    if [ -n "${FAKE_TOUCH_REACH_INV:-}" ]; then
      touch out_reach out_inv
    fi
    if [ -n "${FAKE_SLEEP:-}" ] && [ "${FAKE_SLEEP}" -gt 0 ] 2>/dev/null; then
      sleep "$FAKE_SLEEP"
    fi
    exit "${FAKE_EXIT:-0}"
    ;;
  plot)
    touch out_reach out_inv
    exit "${FAKE_EXIT:-0}"
    ;;
  *)
    echo "FAKE OUTPUT $1"
    exit "${FAKE_EXIT:-0}"
    ;;
esac
EOF
chmod +x tests/fake-phaverlite
```

- [ ] **Step 3: Direct-invocation smoke test of all three modes**

```bash
echo "=== default ==="
./tests/fake-phaverlite /tmp/x.pha; echo "exit=$?"
echo "=== sweep, FAKE_RESULT=reachable ==="
FAKE_PHAVERLITE_MODE=sweep FAKE_RESULT=reachable ./tests/fake-phaverlite /tmp/x.pha
echo "=== sweep + FAKE_TOUCH_REACH_INV (run in /tmp so we don't litter the repo) ==="
(cd /tmp && FAKE_PHAVERLITE_MODE=sweep FAKE_TOUCH_REACH_INV=1 \
  "$OLDPWD"/tests/fake-phaverlite /tmp/x.pha)
ls -1 /tmp/out_reach /tmp/out_inv 2>&1 | head -3
rm -f /tmp/out_reach /tmp/out_inv
echo "=== plot mode (also in /tmp) ==="
(cd /tmp && FAKE_PHAVERLITE_MODE=plot \
  "$OLDPWD"/tests/fake-phaverlite /tmp/x.pha)
ls -1 /tmp/out_reach /tmp/out_inv 2>&1 | head -3
rm -f /tmp/out_reach /tmp/out_inv
```

Expected output:
```
=== default ===
FAKE OUTPUT /tmp/x.pha
exit=0
=== sweep, FAKE_RESULT=reachable ===
bad is reachable
Time in get_reach_set : 0.42 s
=== sweep + FAKE_TOUCH_REACH_INV (run in /tmp so we don't litter the repo) ===
/tmp/out_inv
/tmp/out_reach
=== plot mode (also in /tmp) ===
/tmp/out_inv
/tmp/out_reach
```

- [ ] **Step 4: Verify sub-project B + C tests still pass (default + sweep modes preserved)**

```bash
bin/test-mode 2>&1 | tail -3
```

Expected: `All 1 test passed.` exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/fake-phaverlite
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project D: extend fake-phaverlite — plot mode + sweep touch hook

Adds FAKE_PHAVERLITE_MODE=plot branch (touches out_reach + out_inv in
cwd, exits $FAKE_EXIT). Adds FAKE_TOUCH_REACH_INV env hook to the
existing sweep mode so it also touches those files when set — needed
by sweep-plot-row deftests. Default and sweep modes preserved exactly.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create `tests/fake-graph` + `tests/fake-open` + extend `bin/test-mode`

**Files:**
- Create: `tests/fake-graph` (executable)
- Create: `tests/fake-open` (executable)
- Modify: `bin/test-mode`

- [ ] **Step 1: Create `tests/fake-graph`**

```bash
cat > tests/fake-graph <<'EOF'
#!/bin/sh
# tests/fake-graph — stand-in for GNU plotutils `graph(1)`. Echoes a
# marker so plot-render tests can verify graph was invoked. The output
# redirection (graph ... > plot.png) is handled in lisp via uiop's
# :output kwarg, so the marker lands in the PNG file path.
echo "FAKE GRAPH OUTPUT"
exit "${FAKE_EXIT:-0}"
EOF
chmod +x tests/fake-graph
```

- [ ] **Step 2: Create `tests/fake-open`**

```bash
cat > tests/fake-open <<'EOF'
#!/bin/sh
# tests/fake-open — stand-in for macOS `open(1)`. Echoes the path it was
# invoked with, exits 0. Used by plot-render tests to verify the launch
# was attempted without actually popping Preview.app.
echo "FAKE OPEN $1"
exit 0
EOF
chmod +x tests/fake-open
```

- [ ] **Step 3: Verify both fakes work**

```bash
./tests/fake-graph; echo "exit=$?"
FAKE_EXIT=2 ./tests/fake-graph; echo "exit=$?"
./tests/fake-open /tmp/foo.png
```

Expected:
```
FAKE GRAPH OUTPUT
exit=0
FAKE GRAPH OUTPUT
exit=2
FAKE OPEN /tmp/foo.png
```

- [ ] **Step 4: Extend `bin/test-mode` to symlink the new fakes**

Read the current `bin/test-mode`. Find the line:

```sh
ln -sf "$REPO/tests/fake-phaverlite" "$REPO/var/test-bin/phaverlite"
```

Insert two more `ln -sf` lines immediately after it:

```sh
ln -sf "$REPO/tests/fake-graph" "$REPO/var/test-bin/graph"
ln -sf "$REPO/tests/fake-open" "$REPO/var/test-bin/open"
```

- [ ] **Step 5: Verify the symlinks land in `var/test-bin/`**

```bash
bin/test-mode 2>&1 | tail -3
ls -la var/test-bin/
```

Expected: `bin/test-mode` exits 0 with all prior oks. `var/test-bin/` contains three symlinks (`phaverlite`, `graph`, `open`) all pointing into `tests/`.

- [ ] **Step 6: Commit**

```bash
git add tests/fake-graph tests/fake-open bin/test-mode
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project D: tests/fake-graph + tests/fake-open + symlink wiring

Two new shell stubs to isolate plot tests from real GNU plotutils
graph(1) and macOS open(1). bin/test-mode symlinks both into
var/test-bin/ next to the existing phaverlite symlink, so plot deftests
shell out to the fakes (PATH-prepended) instead of the real binaries.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Sub-project C touch-up — per-pc subdirs + `:directory` + `template-basename`

**Files:**
- Modify: `src/sweep.lisp`
- Modify: `tests/main.lisp` (sweep-engine deftest assertion + the make-temp-pha-template fixture if needed)

This task changes the sweep engine layout WITHOUT breaking the existing 75-ok suite. The plot-row task (Task 7) depends on the per-pc dirs existing.

**Concrete changes inside `src/sweep.lisp`:**

1. Add `template-basename` slot to `sweep-state` struct.
2. Change `sweep-output-path` to return `var/sweep/<basename>/pc-<formatted-pc>/<basename>.pha`.
3. In `sweep-tick`'s spawn branch, add `:directory pc-dir` to the `uiop:launch-program` call. `pc-dir` is the parent dir of the per-pc materialized .pha.
4. In `run-sweep`, set `template-basename` on the state when constructing it.
5. In `ensure-sweep-buffer`, stash the basename on a buffer-local variable so `phaverlite-sweep-plot-row` can read it after `*active-sweep*` is cleared.

NOTE: defer the `phaverlite-sweep-results-mode` major mode + `p` keybind to Task 7 (where the plot-row command is defined). Adding it here would create a forward reference to `phaverlite-mode/plot:phaverlite-sweep-plot-row` which doesn't exist yet.

- [ ] **Step 1: Read the relevant chunks of `src/sweep.lisp`**

```bash
grep -n 'defstruct sweep-state\|sweep-output-path\|launch-program\|run-sweep\|ensure-sweep-buffer' src/sweep.lisp | head -20
```

Take note of the line numbers; you'll edit at those locations.

- [ ] **Step 2: Add `template-basename` slot to the struct**

Find the `(defstruct sweep-state ...)` form. Add a `template-basename` field at the end of the slot list. Example:

```lisp
(defstruct sweep-state
  template-path
  template-basename                 ; NEW — string, used by plot-row
  output-path
  ...)
```

- [ ] **Step 3: Replace `sweep-output-path` with the per-pc-dir variant**

Find the existing `sweep-output-path` (it returned `var/sweep/<basename>.pha`). Replace its body with one that takes BOTH the template-path AND the pc value, and returns the new layout:

```lisp
(defun sweep-output-path (template-path pc)
  "Where the materialized .pha goes for this pc value:
   var/sweep/<basename>/pc-<formatted-pc>/<basename>.<ext>.
   Each pc gets its own directory so phaverlite's side-effect output
   files (out_reach, out_inv) survive across iterations and can be
   plotted later via phaverlite-sweep-plot-row (sub-project D)."
  (let* ((basename (pathname-name template-path))
         (ext (pathname-type template-path))
         (pc-string (format nil "~F" pc))
         (rel (format nil "var/sweep/~a/pc-~a/~a.~a"
                      basename pc-string basename (or ext "pha"))))
    (merge-pathnames rel (uiop:getcwd))))
```

(Note: this changes the function arity from `(template-path)` to `(template-path pc)`. Update the caller in `sweep-tick` accordingly.)

- [ ] **Step 4: Update `sweep-tick` to pass `pc` to `sweep-output-path` and add `:directory` to the spawn**

Find the `sweep-tick` function. In the spawn-next-pc branch, the existing code computes `out-path` and calls `uiop:launch-program`. Update:

```lisp
;; (in sweep-tick, the "spawn next pc" branch)
(let* ((pc (pop (sweep-state-values state)))
       (out-path (sweep-output-path (sweep-state-template-path state) pc))
       (pc-dir (uiop:pathname-directory-pathname out-path)))
  (setf (sweep-state-current-pc state) pc)
  (write-status-line (sweep-state-buffer state)
                     (sweep-state-done state)
                     (sweep-state-total state)
                     (format nil "current: pc=~a" pc))
  (handler-case
      (progn
        (ensure-directories-exist out-path)
        (materialize-template (sweep-state-template-path state) out-path pc)
        (let ((proc (uiop:launch-program
                     (list "phaverlite" (namestring out-path))
                     :output :stream
                     :error-output :output
                     :directory pc-dir)))                ; NEW
          (setf (sweep-state-current-process state) proc)
          (start-next-iteration state)))
    (error (e)
      (write-row (sweep-state-buffer state)
                 pc :unknown (format nil "err:~a" e))
      (finalize-sweep state nil))))
```

(Keep the rest of `sweep-tick` — cancel-flag handling, process-poll branch, etc. — unchanged.)

- [ ] **Step 5: Set `template-basename` in `run-sweep`**

Find the `run-sweep` function. Inside, where the `make-sweep-state` call is, add `:template-basename`:

```lisp
(let* ((basename (pathname-name template-path))
       (state (make-sweep-state
                :template-path template-path
                :template-basename basename            ; NEW
                ;; ... existing slots ...
                )))
  ;; ... existing body ...
  )
```

(The exact form depends on how `run-sweep` currently constructs the state. The change is purely additive.)

- [ ] **Step 6: Stash basename on the sweep buffer as a buffer-local variable**

Lem exposes buffer-local vars via `lem:editor-variable` or directly via `(setf (buffer-value buf 'sym) value)` / `(buffer-value buf 'sym)`. API-grep step:

```bash
grep -nE 'defun buffer-value|defun buffer-attribute|setf.*buffer-value' .lem-ref/src/buffer/internal/buffer.lisp 2>/dev/null | head -5
```

Use whichever is exported. The plan assumes `(setf (lem:buffer-value buf 'phaverlite-sweep-template-basename) basename)` works; if lem uses a different name (e.g. `buffer-attribute`), adjust both the setter here and the getter in Task 7.

In `run-sweep`, after creating the buffer and BEFORE setting `*active-sweep*`:

```lisp
;; Stash the basename on a buffer-local var so phaverlite-sweep-plot-row
;; (sub-project D) can find the per-pc dirs after *active-sweep* is
;; cleared on finalize.
(setf (lem:buffer-value buf 'phaverlite-sweep-template-basename) basename)
```

- [ ] **Step 7: Update the `sweep-engine` deftest to assert per-pc dirs exist**

In `tests/main.lisp`, find the `(deftest sweep-engine ...)` form. Inside the happy-path testing block (after `wait-for-sweep-completion` returns true), add:

```lisp
      ;; Per-pc dirs were created with the materialized .pha inside,
      ;; AND phaverlite ran with cwd set there (out_reach/out_inv would
      ;; land there too if the fake binary touched them).
      (let* ((basename (pathname-name path))
             (pc-3-dir (merge-pathnames
                        (format nil "var/sweep/~a/pc-3.0/" basename)
                        (uiop:getcwd))))
        (ok (probe-file (merge-pathnames
                         (format nil "~a.pha" basename) pc-3-dir))
            "per-pc dir contains the materialized .pha"))
```

(Adapt the basename / pc-value variants to whatever `make-temp-pha-template` actually produces and whatever range the engine deftest uses.)

If the existing `sweep-engine` deftest has any literal-path assertion against `var/sweep/<basename>.pha` (the old flat layout), update it to the new layout: `var/sweep/<basename>/pc-<v>/<basename>.pha`.

- [ ] **Step 8: Run the test suite, verify everything still passes (with the new assertion)**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: all prior oks still green. The new "per-pc dir contains the materialized .pha" assertion passes.

If the per-pc dir assertion fails, double-check:
- `sweep-output-path` returns the right string format (`var/sweep/<basename>/pc-<pc>/<basename>.pha`).
- `ensure-directories-exist` is called BEFORE `materialize-template`.
- The pc-string formatting matches between the path computation and what you assert in the test (both use `(format nil "~F" pc)`).

- [ ] **Step 9: Verify the live sweep still works end-to-end**

Quick sanity: rebuild the image and run a tiny sweep.

```bash
bin/build-image 2>&1 | tail -2
ls -la var/sweep/ 2>/dev/null  # should be empty or have stale data from prior sweeps
```

(The interactive smoke test for a real sweep is in Task 8; this step just confirms the image rebuilds cleanly with the touch-up.)

- [ ] **Step 10: Commit**

```bash
git add src/sweep.lisp tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project D / C touch-up: per-pc subdirs in sweep engine

Each sweep iteration now runs in var/sweep/<basename>/pc-<value>/ as
its cwd, so phaverlite's side-effect files (out_reach, out_inv) land
in that per-pc directory and survive across iterations. Required by
sub-project D's phaverlite-sweep-plot-row command, which needs the
per-pc data to invoke graph(1).

Changes:
- sweep-output-path takes (template-path pc), returns the per-pc
  layout instead of the old flat var/sweep/<basename>.pha.
- sweep-tick spawns phaverlite with :directory pc-dir.
- sweep-state gains a template-basename slot, stashed on the sweep
  buffer as a buffer-local var so the plot-row command can locate the
  per-pc dirs after *active-sweep* is cleared.
- sweep-engine deftest gains an assertion for the per-pc layout.

Defers the *phaverlite-sweep* p keybind + phaverlite-sweep-results-mode
to a later commit (sub-project D Task 7) where the plot-row command
itself is defined.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `render-plot-dir` primitive — TDD

**Files:**
- Modify: `src/plot.lisp` (add primitive)
- Modify: `tests/main.lisp` (add `plot-render` deftest)

- [ ] **Step 1: Write the failing test**

Append to `tests/main.lisp`:

```lisp
(defun make-temp-plot-dir-with-files (&key (with-reach t) (with-inv t))
  "Create a fresh temp dir with optional out_reach + out_inv files.
   Returns the dir as an absolute pathname."
  (let* ((dir (merge-pathnames
               (format nil "phaverlite-plot-test-~a/" (get-universal-time))
               (uiop:temporary-directory))))
    (ensure-directories-exist dir)
    (when with-reach
      (with-open-file (s (merge-pathnames "out_reach" dir)
                         :direction :output :if-exists :supersede)
        (write-string "1 2 0
3 4 0
" s)))
    (when with-inv
      (with-open-file (s (merge-pathnames "out_inv" dir)
                         :direction :output :if-exists :supersede)
        (write-string "0 0 0
5 5 0
" s)))
    dir))

(defun stub-message-collector ()
  "Stub lem:message to collect messages into a list. Returns two values:
   (1) a thunk to install the stub, (2) a thunk to read the collected
   list and uninstall."
  (let ((collected '())
        (original (fdefinition 'lem:message)))
    (values
     (lambda ()
       #+sbcl (sb-ext:without-package-locks
                (setf (fdefinition 'lem:message)
                      (lambda (fmt &rest args)
                        (push (apply #'format nil fmt args) collected))))
       #-sbcl (setf (fdefinition 'lem:message)
                    (lambda (fmt &rest args)
                      (push (apply #'format nil fmt args) collected))))
     (lambda ()
       (prog1 (nreverse collected)
         #+sbcl (sb-ext:without-package-locks
                  (setf (fdefinition 'lem:message) original))
         #-sbcl (setf (fdefinition 'lem:message) original))))))

(deftest plot-render
  (testing "both files present → plot.png is written"
    (let ((dir (make-temp-plot-dir-with-files :with-reach t :with-inv t)))
      (multiple-value-bind (install collect) (stub-message-collector)
        (funcall install)
        (let ((result (phaverlite-mode/plot::render-plot-dir dir)))
          (let ((messages (funcall collect)))
            (declare (ignore messages))
            (ok (probe-file (merge-pathnames "plot.png" dir)))
            (ok (truename result))                         ; non-NIL return
            (ok (search "FAKE GRAPH OUTPUT"
                        (uiop:read-file-string
                         (merge-pathnames "plot.png" dir)))))))))
  (testing "out_reach missing → message + return NIL + no plot.png"
    (let ((dir (make-temp-plot-dir-with-files :with-reach nil :with-inv t)))
      (multiple-value-bind (install collect) (stub-message-collector)
        (funcall install)
        (let ((result (phaverlite-mode/plot::render-plot-dir dir)))
          (let ((messages (funcall collect)))
            (ok (null result))
            (ok (some (lambda (m) (search "out_reach" m)) messages))
            (ok (not (probe-file (merge-pathnames "plot.png" dir)))))))))
  (testing "out_inv missing → message + return NIL + no plot.png"
    (let ((dir (make-temp-plot-dir-with-files :with-reach t :with-inv nil)))
      (multiple-value-bind (install collect) (stub-message-collector)
        (funcall install)
        (let ((result (phaverlite-mode/plot::render-plot-dir dir)))
          (let ((messages (funcall collect)))
            (ok (null result))
            (ok (some (lambda (m) (search "out_inv" m)) messages))
            (ok (not (probe-file (merge-pathnames "plot.png" dir))))))))))
```

- [ ] **Step 2: Run, verify failure**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: `plot-render` fails — `render-plot-dir` undefined.

- [ ] **Step 3: Implement `render-plot-dir` in `src/plot.lisp`**

Append to `src/plot.lisp`:

```lisp
;;; --- constants -----------------------------------------------------------

(defparameter *output-buffer-name* "*phaverlite-plot*"
  "Audit buffer for plot status messages.")

(defparameter +plot-filename+ "plot.png")
(defparameter +reach-filename+ "out_reach")
(defparameter +inv-filename+   "out_inv")

;;; --- primitive: render a directory of phaverlite output -----------------

(defun ensure-plot-buffer ()
  "Get-or-create the *phaverlite-plot* audit buffer."
  (or (lem:get-buffer *output-buffer-name*)
      (lem:make-buffer *output-buffer-name*)))

(defun append-plot-line (text)
  "Append TEXT (no trailing newline) + newline to the *phaverlite-plot*
   audit buffer."
  (let* ((buf (ensure-plot-buffer))
         (p (lem:buffer-end-point buf)))
    (lem:insert-string p text)
    (lem:insert-character p #\newline)))

(defun render-plot-dir (dir)
  "Render DIR's out_reach + out_inv to DIR/plot.png via graph(1), then
   open the PNG in the system viewer (`open` on macOS). Returns the
   plot.png pathname on success, NIL on any failure (precondition,
   graph error, etc.) — failures surface via lem:message and the
   *phaverlite-plot* audit buffer."
  (let* ((dir (uiop:ensure-directory-pathname dir))
         (reach (merge-pathnames +reach-filename+ dir))
         (inv   (merge-pathnames +inv-filename+ dir))
         (plot  (merge-pathnames +plot-filename+ dir)))
    (cond
      ((not (probe-file reach))
       (lem:message "Plot: no ~a in ~a (did your .pha use .print?)"
                    +reach-filename+ dir)
       (append-plot-line (format nil "missing: ~a" reach))
       nil)
      ((not (probe-file inv))
       (lem:message "Plot: no ~a in ~a (did your .pha use .print?)"
                    +inv-filename+ dir)
       (append-plot-line (format nil "missing: ~a" inv))
       nil)
      (t
       (handler-case
           (progn
             ;; graph -T png -C -B -q 0.1 <inv> -C -q 0.5 <reach> > <plot>
             (with-open-file (out plot :direction :output
                                       :if-exists :supersede
                                       :element-type '(unsigned-byte 8))
               (uiop:run-program
                (list "graph" "-T" "png" "-C" "-B"
                      "-q" "0.1" (namestring inv)
                      "-C"
                      "-q" "0.5" (namestring reach))
                :output out
                :error-output :string))
             (handler-case
                 (uiop:launch-program (list "open" (namestring plot)))
               (error (e)
                 (lem:message "open failed: ~a; plot at ~a" e plot)
                 (append-plot-line (format nil "open failed: ~a" e))))
             (lem:message "Plot: ~a" plot)
             (append-plot-line (format nil "rendered: ~a" plot))
             plot)
         (error (e)
           (lem:message "graph failed: ~a" e)
           (append-plot-line (format nil "graph failed: ~a" e))
           nil))))))
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -5
```

Expected: `plot-render` PASS (3 testing forms). All prior oks still green.

If "both files present" test fails because `plot.png` doesn't contain `FAKE GRAPH OUTPUT`, the lisp-side redirection isn't capturing fake-graph's stdout. Possible cause: opening the file with `:element-type '(unsigned-byte 8))` and passing to `:output` — uiop should accept it but if there's a binary/character mismatch, switch to `:element-type 'character`.

If "graph not on PATH" symptoms appear (the test would still pass the missing-file branches but fail the "both files present" one with a different error), the test runner symlinks aren't on PATH. Verify that `bin/test-mode` ran the `ln -sf "$REPO/tests/fake-graph" "$REPO/var/test-bin/graph"` line and that `var/test-bin` is first in PATH.

- [ ] **Step 5: Commit**

```bash
git add src/plot.lisp tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project D: render-plot-dir primitive

Core primitive shared by both plot surfaces (M-x phaverlite-plot-buffer
and `p` on a sweep row). Validates DIR/out_reach + DIR/out_inv exist,
invokes graph(1) with the spec's recipe (no title, hardcoded filenames),
redirects PNG output to DIR/plot.png via uiop's :output kwarg, then
launches `open` on the result. All failures messaged via lem:message
and recorded in *phaverlite-plot* audit buffer; returns NIL on any
failure, plot.png pathname on success.

Tests: plot-render deftest covers the three branches (both files
present, out_reach missing, out_inv missing) using temp dirs and a
stubbed lem:message collector.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `phaverlite-plot-buffer` interactive command — TDD

**Files:**
- Modify: `src/plot.lisp`
- Modify: `tests/main.lisp`

- [ ] **Step 1: Write the failing test**

Append to `tests/main.lisp`:

```lisp
(defun make-temp-plot-pha-buffer ()
  "Create a buffer visiting a temp .pha file with arbitrary content
   (the fake phaverlite ignores the file content; what matters is the
   buffer-filename)."
  (let* ((path (merge-pathnames
                (format nil "phaverlite-plot-cmd-~a.pha" (get-universal-time))
                (uiop:temporary-directory))))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (write-string "automaton t end" s))
    (lem:find-file-buffer path)))

(deftest plot-buffer-command
  (testing "happy path: phaverlite-plot-buffer creates plot.png"
    (let ((buf (make-temp-plot-pha-buffer)))
      (sb-ext:with-environment-variables
          (("FAKE_PHAVERLITE_MODE" "plot"))
        (with-stubbed-prompt t
          (lambda ()
            (phaverlite-mode/plot:phaverlite-plot-buffer buf))))
      (let* ((basename (pathname-name (lem:buffer-filename buf)))
             (expected-plot (merge-pathnames
                             (format nil "var/plot/~a/plot.png" basename)
                             (uiop:getcwd))))
        (ok (probe-file expected-plot))
        (ok (search "FAKE GRAPH OUTPUT"
                    (uiop:read-file-string expected-plot))))))
  (testing "refuses when *active-sweep* is non-nil"
    (let ((phaverlite-mode/sweep::*active-sweep*
            (phaverlite-mode/sweep::make-sweep-state
             :template-path "x" :template-basename "x"
             :output-path "x" :values nil :total 0 :done 0
             :current-pc nil :current-process nil
             :cancel-flag nil :buffer nil :timer nil))
          (buf (make-temp-plot-pha-buffer)))
      (multiple-value-bind (install collect) (stub-message-collector)
        (funcall install)
        (phaverlite-mode/plot:phaverlite-plot-buffer buf)
        (let ((messages (funcall collect)))
          (ok (some (lambda (m) (search "Sweep in progress" m)) messages)))
        (setf phaverlite-mode/sweep::*active-sweep* nil)))))
```

- [ ] **Step 2: Run, verify failure**

```bash
bin/test-mode 2>&1 | tail -5
```

Expected: `plot-buffer-command` fails — `phaverlite-plot-buffer` undefined.

- [ ] **Step 3: Implement `phaverlite-plot-buffer` in `src/plot.lisp`**

Append:

```lisp
;;; --- M-x phaverlite-plot-buffer (single-run plot command) ---------------

(defun plot-dir-for-template (template-path)
  "Where standalone-plot output goes for a given .pha source:
   var/plot/<basename>/."
  (let ((basename (pathname-name template-path)))
    (merge-pathnames (format nil "var/plot/~a/" basename)
                     (uiop:getcwd))))

(define-command phaverlite-plot-buffer (&optional buffer) ()
  "Run phaverlite on the current .pha buffer in a per-buffer plot dir,
   then render and open the resulting plot. Refuses if a sweep is in
   progress (use `p` on a sweep row instead). Same buffer-precondition
   pattern as phaverlite-run-buffer (must visit a file; modified-buffer
   y/n prompt)."
  (let* ((buf (or buffer (lem:current-buffer)))
         (path (lem:buffer-filename buf)))
    (cond
      ((null path)
       (lem:message "Buffer not visiting a file"))
      (phaverlite-mode/sweep::*active-sweep*
       (lem:message "Sweep in progress; use 'p' on a sweep row instead"))
      ((and (lem:buffer-modified-p buf)
            (not (lem:prompt-for-y-or-n-p
                  "Buffer modified. Save and run plot?")))
       nil)                                ; silent abort
      (t
       (when (lem:buffer-modified-p buf)
         (lem:save-buffer buf))
       (let ((plot-dir (plot-dir-for-template path)))
         (ensure-directories-exist plot-dir)
         (handler-case
             (let ((proc (uiop:launch-program
                          (list "phaverlite" (namestring path))
                          :output :stream
                          :error-output :output
                          :directory plot-dir)))
               ;; Drain stdout into the audit buffer — single short run,
               ;; synchronous wait is fine here (no cancellation in
               ;; prototype's plot path).
               (let ((stream (uiop:process-info-output proc)))
                 (loop for line = (read-line stream nil nil)
                       while line
                       do (append-plot-line line)))
               (uiop:wait-process proc)
               (render-plot-dir plot-dir))
           (error (e)
             (lem:message "phaverlite failed: ~a" e)
             (append-plot-line (format nil "phaverlite failed: ~a" e))
             nil)))))))

;;; --- mode keybinding ----------------------------------------------------

(define-key phaverlite-mode/commands:*phaverlite-mode-keymap*
            "C-c C-p" 'phaverlite-plot-buffer)
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -5
```

Expected: `plot-buffer-command` PASS (2 testing forms). All prior oks still green.

If "happy path" fails with "no out_reach in <dir>", the fake-phaverlite plot mode wasn't activated. Re-check that `(("FAKE_PHAVERLITE_MODE" "plot"))` is correctly set in the test's `with-environment-variables` form, AND that `bin/test-mode`'s `var/test-bin/phaverlite` symlink points at `tests/fake-phaverlite` (which it should from sub-project B / C).

If "refuses when active-sweep" fails, the dummy `make-sweep-state` call's keyword args may not match the real struct. Re-check the sweep-state struct definition (after Task 4's `template-basename` slot addition); add `:template-basename "x"` if missing.

- [ ] **Step 5: Commit**

```bash
git add src/plot.lisp tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project D: phaverlite-plot-buffer command + C-c C-p binding

Standalone plot command. Buffer-precondition pattern mirrors
phaverlite-run-buffer (must visit a file; modified-buffer y/n prompt).
Refuses when a sweep is in progress (delegates to `p` on a sweep row).
Spawns phaverlite with :directory set to var/plot/<basename>/ so its
out_reach/out_inv land there, drains stdout into the *phaverlite-plot*
audit buffer, then calls render-plot-dir. C-c C-p bound at the bottom
of src/plot.lisp (loaded after src/commands.lisp's keymap definition).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `phaverlite-sweep-plot-row` + `phaverlite-sweep-results-mode` + `p` keybind

**Files:**
- Modify: `src/sweep.lisp` (add the major mode + apply in `ensure-sweep-buffer`)
- Modify: `src/plot.lisp` (add the `phaverlite-sweep-plot-row` command + the `p` keybind)
- Modify: `tests/main.lisp` (add `sweep-plot-row` deftest)

This task introduces a thin `phaverlite-sweep-results-mode` major mode whose only job is to scope the `p` keybind to the `*phaverlite-sweep*` buffer (so `p` doesn't shadow self-insert in source files). Same `define-major-mode` pattern as sub-project B's `phaverlite-mode`.

- [ ] **Step 1: API-grep for buffer-value (or buffer-attribute) accessor**

```bash
grep -nE 'defun buffer-value|defmethod buffer-value|setf.*buffer-value|defun buffer-attribute' .lem-ref/src/buffer/internal/buffer.lisp 2>/dev/null
```

Confirm the exact name. The plan uses `lem:buffer-value` in the Task 4 stash; if lem actually uses `buffer-attribute` or another name, update both Task 4's setter and this task's getter.

- [ ] **Step 2: Add `phaverlite-sweep-results-mode` to `src/sweep.lisp`**

Append at the bottom of `src/sweep.lisp` (after the existing `define-key` forms):

```lisp
;;; --- *phaverlite-sweep* buffer mode + keymap ----------------------------

(defparameter *phaverlite-sweep-results-mode-keymap*
  (lem:make-keymap :name '*phaverlite-sweep-results-mode-keymap*))

(lem:define-major-mode phaverlite-sweep-results-mode nil
    (:name "PHAVer-sweep"
     :keymap *phaverlite-sweep-results-mode-keymap*)
  (setf (lem:variable-value 'lem:enable-syntax-highlight) nil))
```

- [ ] **Step 3: Activate the mode in `ensure-sweep-buffer`**

Find `ensure-sweep-buffer` in `src/sweep.lisp`. After it gets-or-creates the buffer and clears it, activate the mode by calling it with the buffer current. The exact pattern from sub-project B's `mode.lisp` uses `define-major-mode`'s auto-generated command, which sets the buffer's major mode when invoked.

```lisp
(defun ensure-sweep-buffer ()
  "Get-or-create the *phaverlite-sweep* buffer; clear it; activate
   phaverlite-sweep-results-mode (so `p` reaches plot-row); return it."
  (let ((buf (or (lem:get-buffer *output-buffer-name*)
                 (lem:make-buffer *output-buffer-name*))))
    (setf (lem:buffer-read-only-p buf) nil)
    (lem:erase-buffer buf)
    ;; Activate the results mode so the buffer-local p keybind takes
    ;; effect. The mode command sets buffer-major-mode internally.
    (lem:with-current-buffer buf
      (phaverlite-sweep-results-mode))
    buf))
```

(If `lem:with-current-buffer` doesn't exist as a name, the equivalent is to bind `lem:*current-buffer*` or call `(setf (lem:current-buffer) buf)` around the mode invocation. API-grep step:

```bash
grep -nE 'defmacro with-current-buffer|defun with-current-buffer' .lem-ref/src/buffer/internal/buffer.lisp 2>/dev/null
```

Use whatever the actual API is. If neither exists, fall back to setting `(setf (lem:buffer-major-mode buf) 'phaverlite-sweep-results-mode)` directly — coarse but functional.)

- [ ] **Step 4: Write the failing `sweep-plot-row` deftest**

Append to `tests/main.lisp`:

```lisp
(deftest sweep-plot-row
  (testing "after a sweep, p on a row creates plot.png in that pc's dir"
    (let ((path (make-temp-pha-template "pc := __PC__;")))
      (sb-ext:with-environment-variables
          (("FAKE_PHAVERLITE_MODE" "sweep")
           ("FAKE_RESULT" "unreachable")
           ("FAKE_CPU" "0.10")
           ("FAKE_TOUCH_REACH_INV" "1"))
        (phaverlite-mode/sweep::run-sweep path 3.0 -1.0 1.0))
      (ok (wait-for-sweep-completion))
      ;; Verify per-pc dirs have out_reach + out_inv (touched by fake).
      (let* ((basename (pathname-name path))
             (pc-3-dir (merge-pathnames
                        (format nil "var/sweep/~a/pc-3.0/" basename)
                        (uiop:getcwd))))
        (ok (probe-file (merge-pathnames "out_reach" pc-3-dir)))
        (ok (probe-file (merge-pathnames "out_inv" pc-3-dir)))
        ;; Switch to *phaverlite-sweep* and call plot-row programmatically.
        ;; (We can't easily simulate "cursor on row N" in rove without a
        ;; live frontend; instead, we directly pass the pc to a slightly
        ;; refactored version of plot-row that takes the pc explicitly.
        ;; OR, we move point on the buffer ourselves.)
        (let* ((sweep-buf (lem:get-buffer "*phaverlite-sweep*"))
               (point (lem:buffer-point sweep-buf)))
          (lem:move-to-line point 7)         ; first row after header
          (lem:line-start point)
          (multiple-value-bind (install collect) (stub-message-collector)
            (funcall install)
            (phaverlite-mode/plot:phaverlite-sweep-plot-row)
            (funcall collect))
          (ok (probe-file (merge-pathnames "plot.png" pc-3-dir)))))))
  (testing "wrong buffer: message and no-op"
    (let ((scratch (lem:make-buffer "*scratch-test*" :temporary t)))
      (lem:with-current-buffer scratch
        (multiple-value-bind (install collect) (stub-message-collector)
          (funcall install)
          (phaverlite-mode/plot:phaverlite-sweep-plot-row)
          (let ((messages (funcall collect)))
            (ok (some (lambda (m) (search "Not in a *phaverlite-sweep*" m))
                      messages))))))))
```

(The "first row after header" line number — 7 — assumes the header is 6 lines (5 from `write-header` + 1 for the row inserted by the first iteration's `write-row`). Adjust if your actual layout differs; eyeball with `bin/test-mode` output if the test fails on row parsing.)

- [ ] **Step 5: Run, verify failure**

Expected: `sweep-plot-row` fails — `phaverlite-sweep-plot-row` undefined.

- [ ] **Step 6: Implement `phaverlite-sweep-plot-row` in `src/plot.lisp`**

Append:

```lisp
;;; --- p on a sweep row (per-pc plot command) -----------------------------

(defun parse-sweep-row-pc (line-text)
  "Return the first whitespace-separated token of LINE-TEXT as a string,
   or NIL if the line doesn't look like a sweep result row."
  (let* ((trimmed (string-trim '(#\space #\tab) line-text))
         (sp (or (position-if (lambda (c) (member c '(#\space #\tab)))
                              trimmed)
                 (length trimmed)))
         (token (subseq trimmed 0 sp)))
    (when (and (plusp (length token))
               ;; Must start with a digit or sign — filters out header,
               ;; status, and separator lines.
               (or (digit-char-p (char token 0))
                   (and (member (char token 0) '(#\- #\+))
                        (> (length token) 1)
                        (digit-char-p (char token 1)))))
      token)))

(defun current-line-text (buffer)
  "Return the text of the line containing BUFFER's point."
  (let ((p (lem:buffer-point buffer))
        (start (lem:copy-point (lem:buffer-point buffer) :temporary))
        (end (lem:copy-point (lem:buffer-point buffer) :temporary)))
    (declare (ignore p))
    (lem:line-start start)
    (lem:line-end end)
    (lem:points-to-string start end)))

(define-command phaverlite-sweep-plot-row () ()
  "Plot the reach-set for the sweep row at point. Operates on the
   *phaverlite-sweep* buffer; reads the pc value from the current line's
   first token."
  (let ((buf (lem:current-buffer)))
    (cond
      ((not (string= (lem:buffer-name buf) "*phaverlite-sweep*"))
       (lem:message "Not in a *phaverlite-sweep* buffer"))
      (t
       (let* ((line (current-line-text buf))
              (pc-token (parse-sweep-row-pc line))
              (basename (lem:buffer-value
                         buf 'phaverlite-sweep-template-basename)))
         (cond
           ((null pc-token)
            (lem:message "No sweep row at point"))
           ((null basename)
            (lem:message "No template basename on sweep buffer (run a sweep first)"))
           (t
            (let ((pc-dir (merge-pathnames
                           (format nil "var/sweep/~a/pc-~a/"
                                   basename pc-token)
                           (uiop:getcwd))))
              (cond
                ((not (uiop:directory-exists-p pc-dir))
                 (lem:message
                  "No plot data for pc=~a (was it cancelled?)" pc-token))
                (t
                 (render-plot-dir pc-dir)))))))))))
```

- [ ] **Step 7: Bind `p` on the sweep results mode keymap (in `src/plot.lisp`)**

Append at the very bottom of `src/plot.lisp` (after the existing `define-key` for `C-c C-p`):

```lisp
;; The phaverlite-sweep-results-mode keymap is defined in src/sweep.lisp
;; and exists by the time plot.lisp loads (asd serial order). Bind p
;; here, after phaverlite-sweep-plot-row exists.
(define-key phaverlite-mode/sweep::*phaverlite-sweep-results-mode-keymap*
            "p" 'phaverlite-sweep-plot-row)
```

(Use `::` because the keymap symbol is internal to phaverlite-mode/sweep — we don't export it. If you'd rather export it cleanly, add it to `src/sweep.lisp`'s `:export` and use `:` here.)

- [ ] **Step 8: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: `sweep-plot-row` PASS (both testing forms). All prior oks still green.

If the "first row after header" line number is wrong, the parse-sweep-row-pc returns NIL and the test gets "No sweep row at point". Eyeball `*phaverlite-sweep*` after a real run (Task 8) or print the buffer text in the test to discover the actual row line number, then adjust.

- [ ] **Step 9: Commit**

```bash
git add src/sweep.lisp src/plot.lisp tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project D: phaverlite-sweep-plot-row + p keybind

Adds phaverlite-sweep-results-mode (a thin major mode in src/sweep.lisp)
to scope the `p` keybind to the *phaverlite-sweep* buffer — `p` does
not shadow self-insert in .pha source files. The mode is activated
inside ensure-sweep-buffer.

The plot-row command in src/plot.lisp parses the pc token from the
current line, looks up the basename from the sweep buffer's
buffer-local var (set by run-sweep in sub-project D's C touch-up), and
calls render-plot-dir on var/sweep/<basename>/pc-<pc>/.

Tests: sweep-plot-row deftest covers happy path (run a 2-value sweep
with FAKE_TOUCH_REACH_INV, then p on first row produces plot.png) and
wrong-buffer refusal.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Smoke test, image rebuild, isolation regression, push

**Files touched (verification only):**
- Regenerated: `var/lem.core`

This task verifies end-to-end DoD on a real launch. No new code; manual smoke checks plus the regression checks.

- [ ] **Step 1: Rebuild the lem core**

```bash
bin/build-image 2>&1 | tail -3
```

Expected: `build-image: done. Output: ...var/lem.core` (~30-60s, 119M).

If you see `Component "phaverlite-mode" not found`, the central-registry push isn't happening inside `build-image` — check that the script has the `pushnew (truename ".") asdf:*central-registry*` line that sub-project B added (commit `3211861`).

If you see `Symbol PHAVERLITE-MODE/PLOT:... not found`, the asd component order is wrong — verify `(:file "plot")` is the LAST entry in `phaverlite-mode.asd`'s components.

- [ ] **Step 2: Final test-mode regression**

```bash
bin/test-mode 2>&1 | tail -3
```

Expected: `All 1 test passed.` exit 0. All sub-project B + C + D oks green.

- [ ] **Step 3: Launch and run smoke test A — standalone plot**

```bash
bin/phaverlite-ide
```

In lem: `C-x C-f Lab3/bouncing_ball.pha` → opens in PHAVer mode.

Press `C-c C-p`. Behavior expected:
- If buffer modified: y/n prompt to save (press y).
- `phaverlite` runs against the file with cwd = `var/plot/bouncing_ball/`. Stdout drains into `*phaverlite-plot*` audit buffer (which you can `C-x b` to inspect).
- After phaverlite exits, `graph` runs and writes `var/plot/bouncing_ball/plot.png`.
- macOS Preview.app pops up showing the plot (red-rectangle invariants + green-polygon reach-set).
- Lem minibuffer shows `Plot: <path>`.

If Preview pops with an empty plot or one missing a stream, check `var/plot/bouncing_ball/` for `out_reach` and `out_inv`. If missing, the user's .pha didn't `.print()` them. (`bouncing_ball.pha` does, as does `heater_template.pha` after sweep.)

- [ ] **Step 4: Smoke test B — sweep + per-row plot**

`C-x C-f Lab3/heater_template.pha`. Press `C-c C-s`. Accept default range `3.0 -0.05 1.0`. Wait for sweep to fill in (or cancel via `C-c C-k` after a few rows complete).

In `*phaverlite-sweep*`, move point onto a result row (say the third row from the top of the table). Press `p`. Expected:
- Preview.app pops up showing that pc value's reach-set.
- Minibuffer: `Plot: <path-to-per-pc-dir>/plot.png`.

If Preview shows an empty plot, the per-pc dir's `out_reach`/`out_inv` may be missing — verify by `ls var/sweep/heater_template/pc-<v>/` from a separate shell. If the files are absent, `phaverlite` ran without writing them (some pc values that fail the reachability check may not produce them). Try a different row.

- [ ] **Step 5: Wrong-buffer test for `p`**

`C-x b *tmp*`. Press `p`. Expected: lem inserts a literal `p` (lem's startup buffer is `*tmp*`, not `*scratch*` — verified in the lem-default-buffers memory). The `p` binding is scoped to `phaverlite-sweep-results-mode`, so it doesn't fire elsewhere.

- [ ] **Step 6: Refusal-when-sweep-in-progress for plot-buffer**

In a `.pha` source buffer, press `C-c C-s` to start a sweep. While the sweep is still running (status line shows `current: pc=…`), switch back to the source buffer and press `C-c C-p`. Expected: minibuffer shows `Sweep in progress; use 'p' on a sweep row instead`. No plot dir created, no `phaverlite` spawned.

- [ ] **Step 7: Buffer-not-visiting-file refusal**

`C-x b *tmp*`. `M-x phaverlite-plot-buffer`. Expected: minibuffer `Buffer not visiting a file`. No plot.

- [ ] **Step 8: Exit lem and verify isolation**

`C-x C-c`. Then:

```bash
bin/verify-isolation
```

Expected: `[verify-isolation] PASS: no changes under watched paths.`

(`verify-isolation` will internally launch lem; just `C-x C-c` again when it does.)

- [ ] **Step 9: Privacy preflight + push (only when user has approved)**

```bash
bin/privacy-preflight unpushed
```

If clean and the user has approved push:

```bash
git push origin main
```

---

## Definition-of-done checklist (verify against spec after Task 8)

- [ ] (DoD 1) `M-x phaverlite-plot-buffer` (and `C-c C-p`) honors all preconditions: visiting-file, not in sweep, modified-buffer y/n prompt; spawns phaverlite with cwd = `var/plot/<basename>/`; calls `render-plot-dir` on completion.
- [ ] (DoD 2) `render-plot-dir` invokes the spec's exact graph recipe and runs `open` on the resulting PNG.
- [ ] (DoD 3) `p` keybind in `*phaverlite-sweep*` invokes `phaverlite-sweep-plot-row`; reads pc from the line at point; looks up `var/sweep/<basename>/pc-<pc>/`; calls `render-plot-dir`.
- [ ] (DoD 4) Sub-project C touch-up: per-pc subdirs, `:directory` kwarg on phaverlite spawn, `template-basename` slot on sweep-state, buffer-local stash on `*phaverlite-sweep*`.
- [ ] (DoD 5) `bin/test-mode` exits 0 with all prior oks intact + new D oks (`plot-render`, `plot-buffer-command`, `sweep-plot-row`).
- [ ] (DoD 6) `bin/verify-isolation` PASS.
- [ ] (DoD 7) Smoke checks pass: standalone plot on `bouncing_ball.pha`; sweep + `p` on `heater_template.pha`.
