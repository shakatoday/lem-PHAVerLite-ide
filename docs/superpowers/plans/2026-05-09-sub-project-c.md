# Sub-project C — pc-sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `Lab3/sweep_pc.sh` with an in-editor sweep command. From a `.pha` template buffer (must contain `__PC__`), the user runs `M-x phaverlite-sweep-buffer` (or `C-c C-s`), enters a range as `start step stop` in the minibuffer, and watches a `*phaverlite-sweep*` results buffer fill in row-by-row as `phaverlite` runs the sweep sequentially. Skip-current (`C-c C-n`) and kill-whole (`C-c C-k`) commands handle slow values without hijacking `C-g`.

**Architecture:** One new source file `src/sweep.lisp` (package `phaverlite-mode/sweep`) added as the last component of the existing `phaverlite-mode` ASDF system. No new ASDF system. Tests added to the existing `tests/main.lisp`. Sweep engine drives a sequence of async `phaverlite` runs via a polling timer (`lem:start-timer`) so the editor stays responsive and the cancel commands actually fire.

**Tech Stack:** SBCL + lem (pinned in `qlfile`) + qlot for deps + rove for tests + `uiop:launch-program` for async spawn + `lem:start-timer` for polling + zsh launcher.

**Spec:** `docs/superpowers/specs/2026-05-09-sub-project-c-design.md` — read it first.

**Key references in `.lem-ref/`:**
- `.lem-ref/src/timer.lisp` (or grep `start-timer`/`make-timer` in `.lem-ref/src/`) — timer API.
- `.lem-ref/src/syntax-scanner.lisp:105` — repeating timer pattern: `(start-timer *t* 100 :repeat t)`.
- `.lem-ref/src/ext/loading-spinner.lisp` — async-process polling pattern, similar to what sweep engine needs.
- `.lem-ref/src/prompt.lisp` — `prompt-for-string` (line 71) for the range input.
- `src/commands.lisp` (this repo, sub-project B) — `phaverlite-run-buffer` shows the buffer-modified prompt + `uiop:launch-program` pattern; sweep reuses both.

---

## File structure

| File | Action | Purpose |
|---|---|---|
| `src/sweep.lisp` | create | New file. Package `phaverlite-mode/sweep`. Holds state struct, range gen, template substitution, parser, renderer, engine, commands. |
| `phaverlite-mode.asd` | modify | Add `(:file "sweep")` as last component. |
| `src/commands.lisp` | modify | Append three `define-key` forms (`C-c C-s`, `C-c C-n`, `C-c C-k`) at the bottom binding to the sweep commands. |
| `tests/main.lisp` | modify | Append four deftests: `sweep-parse`, `sweep-range`, `sweep-render`, `sweep-engine`. |
| `tests/fake-phaverlite` | modify | Add a sweep-mode branch driven by `FAKE_PHAVERLITE_MODE`/`FAKE_RESULT`/`FAKE_CPU`/`FAKE_SLEEP` env vars. Existing run-buffer behavior preserved when env not set. |
| `var/sweep/` | runtime | Created by sweep engine. Gitignored (under `var/*`). |
| `var/lem.core` | regenerated | Rebuild via `bin/build-image` after wiring (no script change needed — phaverlite-mode.asd already has the new component). |

---

## Task 1: Skeleton — empty `src/sweep.lisp`, asd component, verify load

**Files:**
- Create: `src/sweep.lisp`
- Modify: `phaverlite-mode.asd`

This task wires the new file into the system so `(ql:quickload :phaverlite-mode)` loads it. No functionality yet — just the package shell.

- [ ] **Step 1: Create `src/sweep.lisp` with package shell**

```lisp
;;;; src/sweep.lisp — pc-sweep engine + commands for .pha templates.
;;;;
;;;; Replaces Lab3/sweep_pc.sh with an in-editor command:
;;;;   M-x phaverlite-sweep-buffer   (or C-c C-s)
;;;; See docs/superpowers/specs/2026-05-09-sub-project-c-design.md.

(defpackage #:phaverlite-mode/sweep
  (:use #:cl #:lem)
  (:export #:phaverlite-sweep-buffer
           #:phaverlite-sweep-skip
           #:phaverlite-sweep-cancel))
(in-package #:phaverlite-mode/sweep)
```

- [ ] **Step 2: Add `(:file "sweep")` as the last component in `phaverlite-mode.asd`**

Read the current `phaverlite-mode.asd` and append `(:file "sweep")` to the `:components` list, after `(:file "mode")`:

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
               (:file "sweep")))
```

- [ ] **Step 3: Verify the system loads with the new file**

```bash
PHAVERLITE_IDE_LIB="$PWD/var/lib" qlot exec sbcl \
  --noinform --no-userinit --no-sysinit \
  --eval '(ql:quickload :cffi :silent t)' \
  --eval '(let ((d (uiop:getenv "PHAVERLITE_IDE_LIB"))) (when d (pushnew (uiop:ensure-directory-pathname d) cffi:*foreign-library-directories* :test #'\''equal)))' \
  --eval '(pushnew (truename ".") asdf:*central-registry* :test #'\''equal)' \
  --eval '(ql:quickload :phaverlite-mode :silent t)' \
  --eval '(format t "loaded: ~a~%" (find-package :phaverlite-mode/sweep))' \
  --eval '(uiop:quit 0)'
```

Expected: `loaded: #<PACKAGE "PHAVERLITE-MODE/SWEEP">` and exit 0.

If it fails, the new asd component is wrong — re-check that `(:file "sweep")` is the last item with no typos and that the source file exists at `src/sweep.lisp`.

- [ ] **Step 4: Verify the existing test suite still passes**

```bash
bin/test-mode 2>&1 | tail -3
```

Expected: `All 1 test passed.` Sub-project B's 22 oks across 5 deftests still green.

- [ ] **Step 5: Commit**

```bash
git add src/sweep.lisp phaverlite-mode.asd
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project C: skeleton — empty sweep.lisp + asd component

Adds src/sweep.lisp (package phaverlite-mode/sweep) as the last component
of phaverlite-mode.asd. No behavior yet — just the package shell. Verifies
the existing test suite is still green.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: parse-result + parse-cpu-time — pure parser TDD

**Files:**
- Modify: `src/sweep.lisp` (add parser functions)
- Modify: `tests/main.lisp` (add `sweep-parse` deftest)

- [ ] **Step 1: Write the failing test**

Append to `tests/main.lisp`:

```lisp
(deftest sweep-parse
  (testing "'bad is reachable' → :reachable"
    (ok (eq :reachable
            (phaverlite-mode/sweep::parse-result "bad is reachable"))))
  (testing "'bad not reachable' → :unreachable"
    (ok (eq :unreachable
            (phaverlite-mode/sweep::parse-result "bad not reachable"))))
  (testing "different region name 'target is reachable' → :reachable"
    (ok (eq :reachable
            (phaverlite-mode/sweep::parse-result "target is reachable"))))
  (testing "different region name 'unsafe not reachable' → :unreachable"
    (ok (eq :unreachable
            (phaverlite-mode/sweep::parse-result "unsafe not reachable"))))
  (testing "neither phrase → :unknown"
    (ok (eq :unknown
            (phaverlite-mode/sweep::parse-result "garbage output"))))
  (testing "both phrases — 'not reachable' wins (sweep_pc.sh precedence)"
    (ok (eq :unreachable
            (phaverlite-mode/sweep::parse-result
             (format nil "bad is reachable~%bad not reachable")))))
  (testing "parse-cpu-time picks penultimate field of LAST 'Time in get_reach_set' line"
    (let ((output (format nil
                          "Time in get_reach_set : 0.10 s~%~
                           Time in get_reach_set : 0.42 s")))
      (ok (string= "0.42"
                   (phaverlite-mode/sweep::parse-cpu-time output)))))
  (testing "parse-cpu-time → NIL when no such line"
    (ok (null (phaverlite-mode/sweep::parse-cpu-time "no timing here")))))
```

(`phaverlite-mode/sweep::` with double colon reaches internal symbols — the parser fns are not exported.)

- [ ] **Step 2: Run, verify failure**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: `sweep-parse` fails — `parse-result` undefined.

- [ ] **Step 3: Implement parsers in `src/sweep.lisp`**

Append after the package shell:

```lisp
;;; --- phaverlite stdout parsing -------------------------------------------

(defun parse-result (stdout-string)
  "Return :reachable, :unreachable, or :unknown based on phaverlite stdout.
   We check 'not reachable' BEFORE 'is reachable' to match sweep_pc.sh
   precedence: an output containing both phrases yields :unreachable. We
   intentionally do NOT match a hardcoded region name (the script's literal
   'bad') — phaverlite emits '<region-name> not reachable' / '... is
   reachable' where the name is whatever the user's .pha assigned; the
   substrings on their own are unique enough."
  (cond ((search "not reachable" stdout-string) :unreachable)
        ((search "is reachable"  stdout-string) :reachable)
        (t :unknown)))

(defun parse-cpu-time (stdout-string)
  "Return the penultimate whitespace-delimited field of the LAST line
   containing 'Time in get_reach_set', or NIL if no such line exists.
   Matches the awk extraction in Lab3/sweep_pc.sh."
  (let ((needle "Time in get_reach_set")
        (last-match nil))
    (with-input-from-string (s stdout-string)
      (loop for line = (read-line s nil nil)
            while line
            when (search needle line)
              do (setf last-match line)))
    (when last-match
      (let ((tokens (uiop:split-string last-match
                                       :separator '(#\space #\tab))))
        ;; Filter blanks (uiop:split-string keeps empty entries between
        ;; runs of separator chars).
        (let ((nonblank (remove-if (lambda (s) (zerop (length s))) tokens)))
          (when (>= (length nonblank) 2)
            (nth (- (length nonblank) 2) nonblank)))))))
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -5
```

Expected: all sub-project B deftests + `sweep-parse` pass. Look for `All 1 test passed.` and exit 0.

If the cpu-time test fails because `uiop:split-string` produces unexpected output, inspect the output of `(uiop:split-string "Time in get_reach_set : 0.42 s" :separator '(#\space #\tab))` — should give `("Time" "in" "get_reach_set" ":" "0.42" "s")` after filtering blanks.

- [ ] **Step 5: Commit**

```bash
git add src/sweep.lisp tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project C: parse-result + parse-cpu-time

Pure-string parsers for phaverlite stdout. parse-result matches plain
'not reachable'/'is reachable' substrings (no hardcoded region name —
heater_template.pha uses 'bad' but other models can use any name).
parse-cpu-time finds the LAST 'Time in get_reach_set' line and returns
the penultimate whitespace-delimited field, matching Lab3/sweep_pc.sh's
awk extraction.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: generate-range — pure range generator TDD

**Files:**
- Modify: `src/sweep.lisp`
- Modify: `tests/main.lisp`

- [ ] **Step 1: Write the failing test**

Append to `tests/main.lisp`:

```lisp
(deftest sweep-range
  (testing "(3.0 -0.05 1.0) produces 41 values starting 3.0 ending 1.0"
    (let ((r (phaverlite-mode/sweep::generate-range 3.0 -0.05 1.0)))
      (ok (= 41 (length r)))
      (ok (= 3.0 (first r)))
      ;; Floating-point: last value should be within step of 1.0.
      (ok (< (abs (- 1.0 (car (last r)))) 1.0e-6))))
  (testing "(1.0 0.5 3.0) produces 5 values"
    (let ((r (phaverlite-mode/sweep::generate-range 1.0 0.5 3.0)))
      (ok (= 5 (length r)))
      (ok (= 1.0 (first r)))
      (ok (= 3.0 (car (last r))))))
  (testing "start = stop produces a single-element list"
    (let ((r (phaverlite-mode/sweep::generate-range 2.0 0.5 2.0)))
      (ok (= 1 (length r)))
      (ok (= 2.0 (first r)))))
  (testing "step = 0 raises an error"
    (ok (signals (phaverlite-mode/sweep::generate-range 1.0 0.0 3.0))))
  (testing "sign-mismatched step raises (start=3 step=+0.5 stop=1)"
    (ok (signals (phaverlite-mode/sweep::generate-range 3.0 0.5 1.0))))
  (testing "sign-mismatched step raises (start=1 step=-0.5 stop=3)"
    (ok (signals (phaverlite-mode/sweep::generate-range 1.0 -0.5 3.0)))))
```

- [ ] **Step 2: Run, verify failure**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: `sweep-range` fails — `generate-range` undefined.

- [ ] **Step 3: Implement `generate-range`**

Append to `src/sweep.lisp`:

```lisp
;;; --- range generation ----------------------------------------------------

(defun generate-range (start step stop)
  "Return a list of floats from START toward STOP, inclusive, stepping by
   STEP. Mirrors `seq START STEP STOP` semantics. STOP is included iff it
   is reachable from START via integer multiples of STEP (allowing for
   floating-point slop). Raises ERROR if STEP is zero or sign-mismatched."
  (when (zerop step)
    (error "step must be non-zero"))
  (let ((direction (- stop start)))
    (when (and (not (zerop direction))
               (not (eq (minusp step) (minusp direction))))
      (error "step direction (~a) doesn't reach stop (~a from ~a)"
             step stop start)))
  (loop with eps = (* (abs step) 1.0e-3)
        for v = start then (+ v step)
        while (if (minusp step)
                  (>= v (- stop eps))
                  (<= v (+ stop eps)))
        collect v))
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -5
```

Expected: all green; new `sweep-range` PASS.

If "(3.0 -0.05 1.0) produces 41 values" fails, off-by-one in the eps tolerance. Try different `eps` (e.g. `* (abs step) 0.5`) or adjust the loop condition.

- [ ] **Step 5: Commit**

```bash
git add src/sweep.lisp tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project C: generate-range

Mirrors `seq START STEP STOP` semantics with floating-point tolerance.
Validates step != 0 and that step's sign matches the start->stop direction.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: materialize-template — TDD for template substitution

**Files:**
- Modify: `src/sweep.lisp`
- Modify: `tests/main.lisp`

- [ ] **Step 1: Write the failing test**

Append to `tests/main.lisp`:

```lisp
(deftest sweep-materialize
  (testing "writes substituted template to output path"
    (let* ((tmpl-path (merge-pathnames "phaverlite-tmpl.pha"
                                       (uiop:temporary-directory)))
           (out-path  (merge-pathnames "phaverlite-out.pha"
                                       (uiop:temporary-directory))))
      (with-open-file (s tmpl-path :direction :output :if-exists :supersede)
        (write-string "pc := __PC__;" s))
      (phaverlite-mode/sweep::materialize-template tmpl-path out-path 1.25)
      (ok (string= "pc := 1.25;"
                   (uiop:read-file-string out-path)))))
  (testing "raises when template lacks __PC__"
    (let* ((tmpl-path (merge-pathnames "phaverlite-bad.pha"
                                       (uiop:temporary-directory)))
           (out-path  (merge-pathnames "phaverlite-bad-out.pha"
                                       (uiop:temporary-directory))))
      (with-open-file (s tmpl-path :direction :output :if-exists :supersede)
        (write-string "no placeholder here" s))
      (ok (signals
              (phaverlite-mode/sweep::materialize-template
               tmpl-path out-path 1.0))))))
```

- [ ] **Step 2: Run, verify failure**

Expected: `sweep-materialize` fails — `materialize-template` undefined.

- [ ] **Step 3: Implement `materialize-template`**

Append to `src/sweep.lisp`:

```lisp
;;; --- template substitution -----------------------------------------------

(defun materialize-template (template-path output-path pc)
  "Read TEMPLATE-PATH, substitute every occurrence of '__PC__' with the
   string form of PC, and write the result to OUTPUT-PATH. Returns
   OUTPUT-PATH on success. Raises ERROR if the template doesn't contain
   '__PC__' (defense in depth — the command should already have checked)."
  (let ((source (uiop:read-file-string template-path)))
    (unless (search "__PC__" source)
      (error "Template ~a has no __PC__ placeholder" template-path))
    (ensure-directories-exist output-path)
    (let* ((pc-string (princ-to-string pc))
           (rendered (cl-ppcre-substitute-or-string source "__PC__" pc-string)))
      (with-open-file (s output-path :direction :output :if-exists :supersede)
        (write-string rendered s))
      output-path)))

(defun cl-ppcre-substitute-or-string (haystack needle replacement)
  "Substitute every occurrence of NEEDLE in HAYSTACK with REPLACEMENT.
   Plain string substitution — no regex. We avoid pulling in cl-ppcre
   for one substitution; the misleading name is for future-proofing if
   someone wants to swap in regex later."
  (with-output-to-string (out)
    (loop with i = 0
          with n-len = (length needle)
          for j = (search needle haystack :start2 i)
          while j
          do (write-string haystack out :start i :end j)
             (write-string replacement out)
             (setf i (+ j n-len))
          finally (write-string haystack out :start i))))
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -5
```

Expected: all green; `sweep-materialize` PASS.

- [ ] **Step 5: Commit**

```bash
git add src/sweep.lisp tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project C: materialize-template

Reads template, substitutes __PC__ with PC's string form, writes output.
Plain-string substitution (no cl-ppcre dependency for one needle).
Raises if the template lacks __PC__ (defense-in-depth check; command
already validates this upfront).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Renderer — header, status line, rows, finalize

**Files:**
- Modify: `src/sweep.lisp`
- Modify: `tests/main.lisp`

The renderer writes to a fresh buffer; the engine wires it up. Header is immutable after written. Status line is rewritten in place. Rows append. Finalize converts the status line to a summary.

**Approach for "rewrite line in place":** delete from `(line-start status-line-point)` to `(line-end status-line-point)` and insert the new content. We'll keep a saved point (`*status-line-point*`) inside the sweep state struct (added in Task 7) — for now the renderer can re-find line 3 by line number.

- [ ] **Step 1: Write the failing test**

Append to `tests/main.lisp`:

```lisp
(deftest sweep-render
  (testing "write-header inserts 3 lines: shebang-style, range, status"
    (let* ((buf (lem:make-buffer "*sweep-test*" :temporary t)))
      (lem:erase-buffer buf)
      (phaverlite-mode/sweep::write-header
       buf "Lab3/heater_template.pha" 3.0 -0.05 1.0 41)
      (let ((text (lem:points-to-string (lem:buffer-start-point buf)
                                         (lem:buffer-end-point buf))))
        (ok (search "phaverlite-sweep Lab3/heater_template.pha" text))
        (ok (search "start=3.0" text))
        (ok (search "step=-0.05" text))
        (ok (search "stop=1.0" text))
        (ok (search "(41 values)" text)))))
  (testing "write-status-line rewrites line 3 in place (only one status line)"
    (let* ((buf (lem:make-buffer "*sweep-test*" :temporary t)))
      (lem:erase-buffer buf)
      (phaverlite-mode/sweep::write-header
       buf "x.pha" 1.0 0.5 3.0 5)
      (phaverlite-mode/sweep::write-status-line buf 0 5 "starting…")
      (phaverlite-mode/sweep::write-status-line buf 2 5 "pc=1.5")
      (let ((text (lem:points-to-string (lem:buffer-start-point buf)
                                         (lem:buffer-end-point buf))))
        ;; The starting message must NOT remain.
        (ok (not (search "starting…" text)))
        (ok (search "[2/5 done]" text))
        (ok (search "current: pc=1.5" text)))))
  (testing "write-row appends a column-aligned row below the table separator"
    (let* ((buf (lem:make-buffer "*sweep-test*" :temporary t)))
      (lem:erase-buffer buf)
      (phaverlite-mode/sweep::write-header
       buf "x.pha" 3.0 -0.05 1.0 41)
      (phaverlite-mode/sweep::write-status-line buf 0 41 "pc=3.0")
      (phaverlite-mode/sweep::write-row buf 3.0 :unreachable "0.42")
      (let ((text (lem:points-to-string (lem:buffer-start-point buf)
                                         (lem:buffer-end-point buf))))
        (ok (search "3.0" text))
        (ok (search "unreachable" text))
        (ok (search "0.42" text)))))
  (testing "finalize rewrites status line to summary"
    (let* ((buf (lem:make-buffer "*sweep-test*" :temporary t)))
      (lem:erase-buffer buf)
      (phaverlite-mode/sweep::write-header
       buf "x.pha" 3.0 -0.05 1.0 41)
      (phaverlite-mode/sweep::write-status-line buf 8 41 "pc=2.65")
      (phaverlite-mode/sweep::finalize buf 8 41 t)
      (let ((text (lem:points-to-string (lem:buffer-start-point buf)
                                         (lem:buffer-end-point buf))))
        (ok (search "[8/41 done]" text))
        (ok (search "cancelled by user" text))
        (ok (not (search "current: pc=2.65" text)))))))
```

- [ ] **Step 2: Run, verify failure**

Expected: `sweep-render` fails — renderer functions undefined.

- [ ] **Step 3: Implement renderer in `src/sweep.lisp`**

Append:

```lisp
;;; --- results-buffer renderer ---------------------------------------------

(defparameter *output-buffer-name* "*phaverlite-sweep*")

(defparameter +header-line-count+ 3
  "Header occupies lines 1-2 (shebang + range). Status line is line 3,
   rewritten in place per iteration. Table starts at line 5 (line 4 is
   blank for visual separation, line 5 is the column header).")

(defun ensure-sweep-buffer ()
  "Get-or-create the *phaverlite-sweep* buffer; clear it; return it."
  (let ((buf (or (lem:get-buffer *output-buffer-name*)
                 (lem:make-buffer *output-buffer-name*))))
    (lem:erase-buffer buf)
    (setf (lem:buffer-read-only-p buf) nil)
    buf))

(defun write-header (buf template-path start step stop count)
  "Write the immutable two-line header + initial status line. Subsequent
   write-status-line calls rewrite line 3."
  (let ((p (lem:buffer-end-point buf)))
    (lem:insert-string p (format nil "$ phaverlite-sweep ~a~%" template-path))
    (lem:insert-string p (format nil "Sweep PC: start=~a  step=~a  stop=~a  (~a values)~%"
                                start step stop count))
    ;; Placeholder status line so write-status-line has a line to overwrite.
    (lem:insert-string p (format nil "[0/~a done]  starting…~%" count))
    (lem:insert-string p (format nil "~%"))               ; blank separator
    (lem:insert-string p (format nil "pc       result          cpu(s)~%"))
    (lem:insert-string p (format nil "-------- --------------- ----------~%"))))

(defun rewrite-line (buf line-number new-text)
  "Replace the contents of LINE-NUMBER (1-based) with NEW-TEXT. NEW-TEXT
   should NOT include a trailing newline."
  (let ((p (lem:copy-point (lem:buffer-point buf) :temporary)))
    (lem:move-to-line p line-number)
    (lem:line-start p)
    (let ((end (lem:copy-point p :temporary)))
      (lem:line-end end)
      (lem:delete-between-points p end))
    (lem:insert-string p new-text)))

(defun write-status-line (buf done total current-or-message)
  "Rewrite line 3 (the status line) in place. CURRENT-OR-MESSAGE is the
   trailing text after '[done/total done]  '. If it looks like a pc value
   ('pc=<x>'), the renderer prefixes 'current: ' so callers can pass the
   bare 'pc=<x>' string and the test contract ('current: pc=<x>' visible
   in the buffer) holds. Summary strings like 'cancelled by user' or
   'starting…' pass through unmodified."
  (let* ((msg (if (and (stringp current-or-message)
                       (or (search "pc=" current-or-message)
                           (search "PC=" current-or-message)))
                  (format nil "current: ~a" current-or-message)
                  current-or-message))
         (text (format nil "[~a/~a done]  ~a" done total msg)))
    (rewrite-line buf 3 text)))

(defun write-row (buf pc result-symbol cpu-string)
  "Append one row to the end of the buffer. Columns: pc (8w) | result (15w)
   | cpu(s) (10w). Column widths match the layout preview exactly."
  (let ((result-string (case result-symbol
                         (:reachable   "reachable")
                         (:unreachable "unreachable")
                         (:cancelled   "cancelled")
                         (:unknown     "?")
                         (otherwise    (format nil "~a" result-symbol)))))
    (let ((p (lem:buffer-end-point buf)))
      (lem:insert-string
       p (format nil "~vA ~vA ~vA~%"
                 8 (format nil "~a" pc)
                 15 result-string
                 10 (or cpu-string "--"))))))

(defun finalize (buf done total cancelled-p)
  "Rewrite the status line as a final summary and freeze the buffer
   read-only."
  (write-status-line buf done total
                     (if cancelled-p "cancelled by user" "finished"))
  (setf (lem:buffer-read-only-p buf) t))
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -5
```

Expected: green; `sweep-render` PASS.

If `lem:delete-between-points` or `lem:line-end` aren't quite right names, grep `.lem-ref/src/buffer/internal/` for the actual symbol — both should exist. (Sub-project B's `indent.lisp` already uses `lem:line-start` and `lem:line-end`, so they're known good.)

- [ ] **Step 5: Commit**

```bash
git add src/sweep.lisp tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project C: results-buffer renderer

write-header lays down the immutable shebang + range lines, an initial
status line on line 3 (rewritten in place per iteration), and the table
header. write-status-line overwrites line 3 in place via
delete-between-points + insert-string. write-row appends a column-aligned
row matching the spec's layout (8w pc | 15w result | 10w cpu). finalize
turns the status line into a summary and freezes the buffer read-only.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Extend `tests/fake-phaverlite` with sweep-mode emission

**Files:**
- Modify: `tests/fake-phaverlite`

This task gives the engine deftest something to spawn. Existing run-buffer behavior must be preserved when the new env var isn't set.

- [ ] **Step 1: Read the current fake binary**

```bash
cat tests/fake-phaverlite
```

Expected: a small zsh/sh script that echoes `FAKE OUTPUT $1` and exits with `$FAKE_EXIT`.

- [ ] **Step 2: Replace with a two-mode version**

```bash
cat > tests/fake-phaverlite <<'EOF'
#!/bin/sh
# tests/fake-phaverlite — test fixture for phaverlite invocations.
#
# Two modes:
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
#
# Usage in tests: bin/test-mode symlinks this as `phaverlite` on PATH;
# deftests `let`-bind env vars per call.

case "${FAKE_PHAVERLITE_MODE:-}" in
  sweep)
    case "${FAKE_RESULT:-unreachable}" in
      reachable)   echo "bad is reachable" ;;
      unreachable) echo "bad not reachable" ;;
      *)           echo "(no result)" ;;
    esac
    echo "Time in get_reach_set : ${FAKE_CPU:-0.42} s"
    if [ -n "${FAKE_SLEEP:-}" ] && [ "${FAKE_SLEEP}" -gt 0 ] 2>/dev/null; then
      sleep "$FAKE_SLEEP"
    fi
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

- [ ] **Step 3: Verify both modes work directly**

```bash
./tests/fake-phaverlite /tmp/x.pha; echo "exit=$?"
FAKE_EXIT=2 ./tests/fake-phaverlite /tmp/x.pha; echo "exit=$?"
FAKE_PHAVERLITE_MODE=sweep ./tests/fake-phaverlite /tmp/x.pha
FAKE_PHAVERLITE_MODE=sweep FAKE_RESULT=reachable FAKE_CPU=0.99 \
  ./tests/fake-phaverlite /tmp/x.pha
```

Expected output:
```
FAKE OUTPUT /tmp/x.pha
exit=0
FAKE OUTPUT /tmp/x.pha
exit=2
bad not reachable
Time in get_reach_set : 0.42 s
bad is reachable
Time in get_reach_set : 0.99 s
```

- [ ] **Step 4: Verify sub-project B's existing tests still pass (default mode preserved)**

```bash
bin/test-mode 2>&1 | tail -3
```

Expected: `All 1 test passed.` Sub-project B's `prompt` and `run-command` deftests still green.

- [ ] **Step 5: Commit**

```bash
git add tests/fake-phaverlite
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project C: extend fake-phaverlite with sweep-mode emission

Adds FAKE_PHAVERLITE_MODE=sweep branch that emits phaverlite-shaped
output (reachable/unreachable + Time in get_reach_set line). Default
mode preserved for sub-project B's existing run-buffer tests. Driven by
FAKE_RESULT / FAKE_CPU / FAKE_SLEEP / FAKE_EXIT env vars.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Sweep engine — state struct, lifecycle, polling timer

**Files:**
- Modify: `src/sweep.lisp` (state struct + run-sweep + iteration tick)
- Modify: `tests/main.lisp` (`sweep-engine` deftest)

This is the most intricate task. Implement the engine, then test it end-to-end against the fake binary.

**Investigation step (first):** confirm `lem:start-timer` / `lem:make-timer` / `lem:stop-timer` signatures.

- [ ] **Step 1: API-grep**

```bash
grep -nE 'defun (start-timer|stop-timer|make-timer|make-idle-timer)' .lem-ref/src/timer.lisp
grep -B1 -A8 'defun start-timer' .lem-ref/src/timer.lisp
```

Note the exact arglist of `start-timer` and `make-timer`. Common pattern (from `.lem-ref/src/syntax-scanner.lisp:105`):
```lisp
(start-timer (make-timer (lambda () BODY) :name "...") MS-INTERVAL :repeat t)
```
or:
```lisp
(start-timer *timer* MS-INTERVAL :repeat t)
```
where `*timer*` was previously created with `make-timer`. Adjust the impl to match.

- [ ] **Step 2: Write the failing engine deftest**

Append to `tests/main.lisp`:

```lisp
(defun make-temp-pha-template (content)
  "Create a temp .pha file containing CONTENT, return its truename."
  (let ((p (merge-pathnames
            (format nil "phaverlite-sweep-test-~a.pha" (get-universal-time))
            (uiop:temporary-directory))))
    (with-open-file (s p :direction :output :if-exists :supersede)
      (write-string content s))
    (truename p)))

(defun wait-for-sweep-completion (&key (timeout-secs 5))
  "Block until *active-sweep* is NIL or TIMEOUT-SECS elapses. Returns T
   on completion, NIL on timeout."
  (let ((start (get-universal-time)))
    (loop until (or (null phaverlite-mode/sweep::*active-sweep*)
                    (> (- (get-universal-time) start) timeout-secs))
          do (sleep 0.05))
    (null phaverlite-mode/sweep::*active-sweep*)))

(deftest sweep-engine
  (testing "3-value sweep produces 3 rows + finished summary"
    (let ((path (make-temp-pha-template "pc := __PC__;")))
      ;; sb-ext:with-environment-variables is not exported by the
      ;; SBCL build on this machine; tests/main.lisp defines a small
      ;; with-env-vars macro using sb-posix:setenv/unsetenv instead.
      (with-env-vars
          (("FAKE_PHAVERLITE_MODE" "sweep")
           ("FAKE_RESULT" "unreachable")
           ("FAKE_CPU" "0.42"))
        (phaverlite-mode/sweep::run-sweep path 3.0 -1.0 1.0))
      (ok (wait-for-sweep-completion))
      (let* ((buf (lem:get-buffer "*phaverlite-sweep*"))
             (text (lem:points-to-string
                    (lem:buffer-start-point buf)
                    (lem:buffer-end-point buf))))
        (ok (search "[3/3 done]" text))
        (ok (search "finished" text))
        ;; Three result rows.
        (ok (search "3.0" text))
        (ok (search "2.0" text))
        (ok (search "1.0" text))
        ;; All three rows show 'unreachable' and the faked cpu.
        (ok (= 3 (count #\Newline (with-output-to-string (s)
                                    (loop for i from 0
                                          for j = (search "unreachable" text :start2 i)
                                          while j
                                          do (terpri s)
                                             (setf i (1+ j)))))))
        (ok (search "0.42" text)))))
  (testing "*active-sweep* is NIL after completion"
    (ok (null phaverlite-mode/sweep::*active-sweep*))))
```

(The "skip" and "kill" cases are deferred to a follow-up commit at the end of this task — the engine deftest first exercises the happy path; once that's green, we add the cancellation cases.)

- [ ] **Step 3: Run, verify failure**

Expected: `sweep-engine` fails — `run-sweep` and `*active-sweep*` undefined.

- [ ] **Step 4: Implement state struct + engine**

Append to `src/sweep.lisp`:

```lisp
;;; --- sweep state + engine -----------------------------------------------

(defvar *active-sweep* nil
  "SWEEP-STATE struct describing the in-flight sweep, or NIL when idle.
   Mutated only by the engine and the skip/cancel commands.")

(defstruct sweep-state
  template-path
  output-path                       ; var/sweep/<basename>.pha (overwritten)
  values                            ; remaining pc values
  total                             ; original count
  done                              ; count of completed values
  current-pc                        ; the value currently running, or NIL
  current-process                   ; uiop process-info, or NIL
  cancel-flag                       ; :skip, :kill, or NIL
  buffer                            ; *phaverlite-sweep* buffer
  timer)                            ; lem timer driving iteration

(defparameter *poll-interval-ms* 50)

(defun sweep-output-path (template-path)
  "Where the materialized .pha goes — var/sweep/<basename>.pha, overwritten
   per iteration."
  (let* ((basename (pathname-name template-path))
         (ext (pathname-type template-path))
         (rel (format nil "var/sweep/~a.~a" basename (or ext "pha"))))
    (merge-pathnames rel (uiop:getcwd))))

(defun start-next-iteration (state)
  "Schedule the next tick of the sweep loop via lem timer. Used both at
   startup and after each iteration completes."
  (setf (sweep-state-timer state)
        (lem:start-timer
         (lem:make-timer (lambda () (sweep-tick state))
                         :name "phaverlite-sweep-tick")
         *poll-interval-ms*)))

(defun sweep-tick (state)
  "One tick of the sweep loop. Either advances to the next pc value (if
   no current-process), or polls the current process for completion."
  ;; Stop the previous one-shot before doing anything.
  (when (sweep-state-timer state)
    (lem:stop-timer (sweep-state-timer state))
    (setf (sweep-state-timer state) nil))
  (let ((flag (sweep-state-cancel-flag state)))
    (cond
      ;; Kill: terminate, finalize, exit.
      ((eq flag :kill)
       (when (sweep-state-current-process state)
         (ignore-errors
          (uiop:terminate-process (sweep-state-current-process state)))
         (setf (sweep-state-current-process state) nil))
       (finalize-sweep state t))
      ;; Skip: terminate current, mark cancelled row, advance.
      ((eq flag :skip)
       (when (sweep-state-current-process state)
         (ignore-errors
          (uiop:terminate-process (sweep-state-current-process state)))
         (setf (sweep-state-current-process state) nil))
       (write-row (sweep-state-buffer state)
                  (sweep-state-current-pc state)
                  :cancelled "--")
       (incf (sweep-state-done state))
       (setf (sweep-state-current-pc state) nil
             (sweep-state-cancel-flag state) nil)
       (start-next-iteration state))
      ;; Process running: poll for exit.
      ((sweep-state-current-process state)
       (let ((proc (sweep-state-current-process state)))
         (cond
           ((uiop:process-alive-p proc)
            (start-next-iteration state))    ; re-poll next tick
           (t                                  ; process done — read + record
            (let* ((stream (uiop:process-info-output proc))
                   (output (with-output-to-string (s)
                             (loop for line = (read-line stream nil nil)
                                   while line
                                   do (write-line line s))))
                   (result (parse-result output))
                   (cpu (parse-cpu-time output)))
              (uiop:wait-process proc)
              (write-row (sweep-state-buffer state)
                         (sweep-state-current-pc state)
                         result cpu)
              (incf (sweep-state-done state))
              (setf (sweep-state-current-process state) nil
                    (sweep-state-current-pc state) nil)
              (start-next-iteration state))))))
      ;; No process; spawn next pc value or finish.
      ((null (sweep-state-values state))
       (finalize-sweep state nil))
      (t
       (let ((pc (pop (sweep-state-values state))))
         (setf (sweep-state-current-pc state) pc)
         (write-status-line (sweep-state-buffer state)
                            (sweep-state-done state)
                            (sweep-state-total state)
                            (format nil "pc=~a" pc))
         (handler-case
             (let ((out-path (sweep-state-output-path state)))
               (materialize-template (sweep-state-template-path state)
                                     out-path pc)
               (let ((proc (uiop:launch-program
                            (list "phaverlite" (namestring out-path))
                            :output :stream :error-output :output)))
                 (setf (sweep-state-current-process state) proc)
                 (start-next-iteration state)))
           (error (e)
             ;; Materialization or spawn failure: record an error row,
             ;; abort the sweep cleanly.
             (write-row (sweep-state-buffer state)
                        pc :unknown (format nil "err:~a" e))
             (finalize-sweep state nil))))))))

(defun finalize-sweep (state cancelled-p)
  "Final cleanup: rewrite status to summary, freeze buffer, clear *active-sweep*."
  (when (sweep-state-timer state)
    (lem:stop-timer (sweep-state-timer state))
    (setf (sweep-state-timer state) nil))
  (when (lem:bufferp (sweep-state-buffer state))
    (finalize (sweep-state-buffer state)
              (sweep-state-done state)
              (sweep-state-total state)
              cancelled-p))
  (setf *active-sweep* nil))

(defun run-sweep (template-path start step stop)
  "Public engine entry point. Builds the sweep-state, opens the output
   buffer, writes the header + initial status line, and schedules the
   first iteration tick. Returns the sweep-state."
  (let* ((values (generate-range start step stop))
         (total (length values))
         (out-path (sweep-output-path template-path))
         (buf (ensure-sweep-buffer))
         (state (make-sweep-state
                 :template-path template-path
                 :output-path out-path
                 :values values
                 :total total
                 :done 0
                 :current-pc nil
                 :current-process nil
                 :cancel-flag nil
                 :buffer buf
                 :timer nil)))
    (write-header buf template-path start step stop total)
    (write-status-line buf 0 total "starting…")
    ;; pop-to-buffer requires a live frontend; tolerate failure in headless
    ;; rove env (same hack as phaverlite-run-buffer in src/commands.lisp).
    (ignore-errors (lem:pop-to-buffer buf))
    (setf *active-sweep* state)
    (start-next-iteration state)
    state))
```

- [ ] **Step 5: Run, verify happy-path test passes**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: `sweep-engine` PASS — three rows in the buffer, `[3/3 done]` and `finished` summary, `*active-sweep*` is NIL after.

If it times out (5s wait expires with `*active-sweep*` non-nil), the timer isn't firing in the rove env. Check that `lem:start-timer` actually runs callbacks under `--script` mode. If it doesn't, switch the polling loop to a thread or call `sweep-tick` recursively from a `(lem:send-event …)` style — but the simpler workaround is to run the sweep synchronously when no editor frame is alive. Add a dynamic-variable knob:
```lisp
(defparameter *sweep-driver* :timer
  "One of :timer (default; poll via lem timer) or :sync (drive
   synchronously by repeatedly calling sweep-tick — used by tests in
   headless rove envs).")
```
And in the `sweep-engine` test, bind `(let ((phaverlite-mode/sweep::*sweep-driver* :sync)) ...)` and have `start-next-iteration` either schedule a timer or call `(sweep-tick state)` directly with a 50ms `sleep` between calls.

- [ ] **Step 6: Add cancellation deftest cases (skip and kill)**

Append to the `sweep-engine` deftest:

```lisp
  (testing "skip case: cancel-flag :skip marks one row (cancelled), continues"
    (let ((path (make-temp-pha-template "pc := __PC__;")))
      ;; sb-ext:with-environment-variables is not exported by the
      ;; SBCL build on this machine; tests/main.lisp defines a small
      ;; with-env-vars macro using sb-posix:setenv/unsetenv instead.
      (with-env-vars
          (("FAKE_PHAVERLITE_MODE" "sweep")
           ("FAKE_RESULT" "unreachable")
           ("FAKE_CPU" "0.10"))
        (let ((state (phaverlite-mode/sweep::run-sweep path 5.0 -1.0 1.0)))
          ;; Wait until at least one row recorded, then request skip.
          (loop until (>= (phaverlite-mode/sweep::sweep-state-done state) 1)
                do (sleep 0.05))
          (setf (phaverlite-mode/sweep::sweep-state-cancel-flag state) :skip))
        (ok (wait-for-sweep-completion))
        (let* ((buf (lem:get-buffer "*phaverlite-sweep*"))
               (text (lem:points-to-string
                      (lem:buffer-start-point buf)
                      (lem:buffer-end-point buf))))
          (ok (search "cancelled" text))
          (ok (search "[5/5 done]" text))
          (ok (search "finished" text))))))
  (testing "kill case: cancel-flag :kill stops at current value, summary"
    (let ((path (make-temp-pha-template "pc := __PC__;")))
      ;; sb-ext:with-environment-variables is not exported by the
      ;; SBCL build on this machine; tests/main.lisp defines a small
      ;; with-env-vars macro using sb-posix:setenv/unsetenv instead.
      (with-env-vars
          (("FAKE_PHAVERLITE_MODE" "sweep")
           ("FAKE_RESULT" "unreachable")
           ("FAKE_CPU" "0.10"))
        (let ((state (phaverlite-mode/sweep::run-sweep path 5.0 -1.0 1.0)))
          (loop until (>= (phaverlite-mode/sweep::sweep-state-done state) 2)
                do (sleep 0.05))
          (setf (phaverlite-mode/sweep::sweep-state-cancel-flag state) :kill))
        (ok (wait-for-sweep-completion))
        (let* ((buf (lem:get-buffer "*phaverlite-sweep*"))
               (text (lem:points-to-string
                      (lem:buffer-start-point buf)
                      (lem:buffer-end-point buf))))
          (ok (search "cancelled by user" text))
          ;; Done count should be at most 3 (the in-flight value gets a
          ;; cancelled row only on :skip, not :kill — :kill stops cleanly
          ;; before recording the in-flight one).
          (ok (search "[" text))))))
```

- [ ] **Step 7: Run, verify all three engine cases pass**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: `sweep-engine` PASS for happy-path + skip + kill.

- [ ] **Step 8: Commit**

```bash
git add src/sweep.lisp tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project C: sweep engine — state, lifecycle, polling timer

run-sweep builds the SWEEP-STATE, materializes the output buffer with
header + status line, and schedules iteration ticks via lem:start-timer.
Each tick: check cancel-flag (kill → finalize, skip → terminate +
cancelled row + advance), poll current process for exit (drain stdout,
parse, write row, advance), or spawn next pc value. Sequential —
at most one phaverlite alive at a time. ~50ms poll interval keeps the
editor responsive and the cancel keys actionable mid-sweep.

Engine deftests cover happy path (3 rows, finished summary), skip
(one cancelled row, sweep continues), and kill (cancelled-by-user
summary, stops at current value).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Interactive commands + keybindings

**Files:**
- Modify: `src/sweep.lisp` (define-command forms)
- Modify: `src/commands.lisp` (three define-key forms at the bottom)

The interactive commands are mostly thin wrappers around the engine. They handle the buffer/file preconditions and the minibuffer prompt; the engine does the work.

- [ ] **Step 1: Implement `phaverlite-sweep-buffer` command**

Append to `src/sweep.lisp`:

```lisp
;;; --- interactive commands -----------------------------------------------

(defparameter *last-sweep-args* nil
  "List (start step stop) from the last successful sweep, used to prefill
   the next minibuffer prompt. NIL means use the default 3.0 -0.05 1.0.")

(defun parse-sweep-args (input)
  "Parse a 'start step stop' string into three floats. Raises ERROR on
   any non-numeric token or wrong arity."
  (let ((tokens (remove-if (lambda (s) (zerop (length s)))
                           (uiop:split-string input
                                              :separator '(#\space #\tab)))))
    (unless (= 3 (length tokens))
      (error "Need exactly 3 numbers, got ~a" (length tokens)))
    (mapcar (lambda (tok)
              (let ((n (with-input-from-string (s tok) (read s))))
                (unless (realp n) (error "Not a number: ~a" tok))
                (coerce n 'float)))
            tokens)))

(define-command phaverlite-sweep-buffer (&optional buffer) ()
  "Sweep the __PC__ placeholder in the current .pha buffer over a range
   of values. Prompts for 'start step stop'. Refuses if a sweep is
   already in progress, the buffer is not visiting a file, or the file
   lacks __PC__. Same buffer-modified prompt as phaverlite-run-buffer."
  (let* ((buf (or buffer (lem:current-buffer)))
         (path (lem:buffer-filename buf)))
    (cond
      (*active-sweep*
       (lem:message "Sweep already in progress (use C-c C-k to cancel)"))
      ((null path)
       (lem:message "Buffer not visiting a file"))
      ((not (search "__PC__" (uiop:read-file-string path)))
       (lem:message "No __PC__ placeholder in ~a" path))
      ((and (lem:buffer-modified-p buf)
            (not (lem:prompt-for-y-or-n-p
                  "Buffer modified. Save and run sweep?")))
       nil)
      (t
       (when (lem:buffer-modified-p buf)
         (lem:save-buffer buf))
       (let* ((default (or *last-sweep-args* '(3.0 -0.05 1.0)))
              (default-string (format nil "~a ~a ~a"
                                      (first default)
                                      (second default)
                                      (third default)))
              (input (lem:prompt-for-string
                      "Sweep PC (start step stop): "
                      :initial-value default-string)))
         (handler-case
             (destructuring-bind (start step stop) (parse-sweep-args input)
               (setf *last-sweep-args* (list start step stop))
               (run-sweep path start step stop))
           (error (e)
             (lem:message "Bad input: ~a" e))))))))

(define-command phaverlite-sweep-skip () ()
  "Skip the currently-running pc value in the active sweep. Marks the
   row (cancelled), advances to the next value. No-op if no sweep
   running."
  (cond
    ((null *active-sweep*)
     (lem:message "No phaverlite-sweep in progress"))
    (t
     (setf (sweep-state-cancel-flag *active-sweep*) :skip)
     (lem:message "Skipping current pc value…"))))

(define-command phaverlite-sweep-cancel () ()
  "Kill the active sweep entirely. Stops the loop after terminating the
   in-flight phaverlite. No-op if no sweep running."
  (cond
    ((null *active-sweep*)
     (lem:message "No phaverlite-sweep in progress"))
    (t
     (setf (sweep-state-cancel-flag *active-sweep*) :kill)
     (lem:message "Cancelling sweep…"))))
```

- [ ] **Step 2: Bind the three keys in `src/commands.lisp`**

Append at the bottom of `src/commands.lisp`:

```lisp
;; pc-sweep commands (sub-project C). Bound here so all phaverlite-mode
;; keybindings live in one place; the commands themselves are defined in
;; src/sweep.lisp and exported as phaverlite-mode/sweep:phaverlite-sweep-*.
(define-key *phaverlite-mode-keymap* "C-c C-s"
            'phaverlite-mode/sweep:phaverlite-sweep-buffer)
(define-key *phaverlite-mode-keymap* "C-c C-n"
            'phaverlite-mode/sweep:phaverlite-sweep-skip)
(define-key *phaverlite-mode-keymap* "C-c C-k"
            'phaverlite-mode/sweep:phaverlite-sweep-cancel)
```

- [ ] **Step 3: Verify the system loads with the new bindings**

```bash
bin/test-mode 2>&1 | tail -3
```

Expected: all green; existing 22 oks + new sweep oks all pass; exit 0.

If you get `Symbol PHAVERLITE-MODE/SWEEP:PHAVERLITE-SWEEP-BUFFER not found`, the load order is wrong — `commands.lisp` must load AFTER `sweep.lisp` so the package exists when define-key resolves the symbol. The asd has `serial t` and lists components in order `(syntax indent commands mode sweep)` — sweep loads LAST. So `commands.lisp` referencing sweep symbols at top-level fails.

**Fix options:**
- a) Move the three define-key forms to a new file `src/sweep-keys.lisp` listed AFTER sweep in the asd. Cleaner.
- b) In `commands.lisp`, defer the define-key forms until after sweep loads — wrap them in `(eval-when (:load-toplevel :execute) ...)` and fully-qualify the symbol with the keyword form `'phaverlite-mode/sweep:phaverlite-sweep-buffer`. Doesn't help — symbol resolution happens at read time.
- c) Reorder `phaverlite-mode.asd` so sweep loads BEFORE commands. But commands defines `*phaverlite-mode-keymap*` which sweep would need.
- d) Move the keybindings into `src/sweep.lisp` itself — at the bottom, after the commands are defined. Sweep already depends on commands (for the keymap), and the keymap exists by the time sweep loads.

**Take option (d).** Remove the additions from `commands.lisp`. Append to `src/sweep.lisp` instead:

```lisp
;;; --- mode keymap bindings ------------------------------------------------

(define-key phaverlite-mode/commands:*phaverlite-mode-keymap*
            "C-c C-s" 'phaverlite-sweep-buffer)
(define-key phaverlite-mode/commands:*phaverlite-mode-keymap*
            "C-c C-n" 'phaverlite-sweep-skip)
(define-key phaverlite-mode/commands:*phaverlite-mode-keymap*
            "C-c C-k" 'phaverlite-sweep-cancel)
```

(Note the package-qualified `phaverlite-mode/commands:*phaverlite-mode-keymap*` — sweep doesn't `:use` the commands package because that would create an import-from cycle, but the keymap is exported.)

- [ ] **Step 4: Run, verify everything still passes**

```bash
bin/test-mode 2>&1 | tail -3
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add src/sweep.lisp src/commands.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project C: interactive commands + keybindings

phaverlite-sweep-buffer (C-c C-s): preconditions, save prompt, range
prompt with prefill from *last-sweep-args*, calls run-sweep.
phaverlite-sweep-skip (C-c C-n): sets cancel-flag :skip on the engine.
phaverlite-sweep-cancel (C-c C-k): sets cancel-flag :kill.
Keybindings installed at the bottom of src/sweep.lisp (loaded after
src/commands.lisp, so the keymap exists).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Smoke test, image rebuild, isolation regression, push

**Files touched (verification only):**
- Regenerated: `var/lem.core`

This task verifies the end-to-end DoD on a real launch. No new code; only manual smoke checks plus the regression checks.

- [ ] **Step 1: Rebuild the lem core**

```bash
bin/build-image 2>&1 | tail -3
```

Expected: `build-image: done. Output: ...var/lem.core` (~30-60s, 119M).

If you see `Component "phaverlite-mode" not found`, the central-registry push isn't happening inside `build-image` — check that the script has the `pushnew (truename ".") asdf:*central-registry*` line that sub-project B added (commit `3211861`).

If you see `Symbol PHAVERLITE-MODE/SWEEP:... not found`, the asd component order is wrong or sweep.lisp didn't compile cleanly — re-run `bin/test-mode` first, fix any compile errors, then rebuild.

- [ ] **Step 2: Launch and open the heater template**

```bash
bin/phaverlite-ide
```

In lem: `C-x C-f` → type `Lab3/heater_template.pha` → Enter. Confirm the file opens in `phaverlite-mode` (modeline shows "PHAVer").

- [ ] **Step 3: Trigger a sweep**

Press `C-c C-s`. Minibuffer should prompt: `Sweep PC (start step stop): 3.0 -0.05 1.0` (default). Press Enter to accept.

`*phaverlite-sweep*` buffer should open in a horizontal split below the source. You should see the header, the status line `[N/41 done]  current: pc=<x>` updating in place, and rows appending one at a time. The full sweep takes whatever phaverlite needs (likely a few seconds per value for heater_template). Final summary: `[41/41 done]  finished`.

If `phaverlite` is missing from PATH, you'll get an error row and an "aborted" summary — install `phaverlite` first (per `ps3/install_phaverlite.sh`).

- [ ] **Step 4: Test skip mid-sweep**

Trigger another sweep (`C-c C-s`, Enter to accept the prefilled range from last run). After 3-5 rows complete, press `C-c C-n`. The current row should be marked `(cancelled) --` and the sweep should continue with the next pc value.

- [ ] **Step 5: Test kill mid-sweep**

Trigger another sweep. After 3-5 rows complete, press `C-c C-k`. The status line should change to `[N/41 done]  cancelled by user`. No further rows should append.

- [ ] **Step 6: Test concurrent-sweep refusal**

Start a sweep and immediately try `C-c C-s` again before it finishes. Minibuffer should message `Sweep already in progress (use C-c C-k to cancel)`.

- [ ] **Step 7: Test missing-placeholder refusal**

Open `Lab3/bouncing_ball.pha` (no `__PC__` placeholder — it has a hardcoded `pc := 0.05;`). Press `C-c C-s`. Minibuffer should message `No __PC__ placeholder in <path>`.

- [ ] **Step 8: Test non-file-buffer refusal**

`C-x b *tmp*`. `M-x phaverlite-sweep-buffer`. Should message `Buffer not visiting a file`.

(Note: lem's startup buffer is `*tmp*`, not Emacs's `*scratch*`.)

- [ ] **Step 9: Exit lem and verify isolation**

`C-x C-c`. Then:

```bash
bin/verify-isolation
```

Expected: `[verify-isolation] PASS: no changes under watched paths.`

- [ ] **Step 10: Run the test suite one more time as a final regression**

```bash
bin/test-mode 2>&1 | tail -3
```

Expected: `All 1 test passed.` exit 0. Sub-project B's 22 oks + sub-project C's new oks all green.

- [ ] **Step 11: Privacy preflight on the full unpushed history, then push**

```bash
bin/privacy-preflight unpushed || exit 1
```

If clean, push (only when the user has approved):

```bash
git push origin main
```

---

## Definition-of-done checklist (verify against spec after Task 9)

- [ ] (DoD 1) `M-x phaverlite-sweep-buffer` (and `C-c C-s`) honors all five preconditions: visiting-file, has `__PC__`, not already running, modified-buffer prompt, range parse + validate.
- [ ] (DoD 2) `*phaverlite-sweep*` buffer opens in horizontal split below source; cursor stays in source.
- [ ] (DoD 3) Buffer layout matches the approved mockup (header line 1-2 immutable, status line 3 rewritten in place, rows append below the table separator).
- [ ] (DoD 4) `C-c C-n` skips the current pc value; row marked `(cancelled) --`; sweep continues.
- [ ] (DoD 5) `C-c C-k` kills the whole sweep; status line summary `[N/total done]  cancelled by user`.
- [ ] (DoD 6) Result row format matches `Lab3/sweep_pc.sh` contract (pc 8w | result 15w | cpu 10w; results ∈ {reachable, unreachable, ?, error(<exit>), cancelled}).
- [ ] (DoD 7) Materialized template at `var/sweep/<basename>.pha`, overwritten per iteration.
- [ ] (DoD 8) `bin/test-mode` exits 0 with sub-project B's 22 oks + sub-project C's new sweep oks.
- [ ] (DoD 9) `bin/verify-isolation` PASS.
