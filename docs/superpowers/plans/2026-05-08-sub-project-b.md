# Sub-project B — phaverlite-mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land a `.pha` major mode in lem with PHAVer-aware syntax highlighting, block-aware indentation, comment toggling, and an `M-x phaverlite-run-buffer` command (also bound to `C-c C-c`) that runs `phaverlite` on the current file and shows its output in a horizontal split below.

**Architecture:** One ASDF system (`phaverlite-mode`) with the asd at repo root (`:pathname "src"`) and four source files directly under `src/`, each in its own package using lem's `/` sub-module convention. A separate test system (`phaverlite-mode-tests`) at repo root runs against the rove framework via `(asdf:test-system :phaverlite-mode-tests)`. Source layout follows lem's own convention (see `.lem-ref/lem.asd`, `.lem-ref/extensions/dot-mode/dot-mode.lisp`, `.lem-ref/extensions/c-mode/c-mode.lisp` for reference patterns).

**Tech Stack:** SBCL + lem (pinned in `qlfile`) + qlot for deps + rove for tests + uiop for process spawn + zsh launcher.

**Spec:** `docs/superpowers/specs/2026-05-08-sub-project-b-design.md` — read it first.

**Spec deviation:** Spec mentions `lem:*auto-mode-alist*`. Lem's actual public API is `lem:define-file-type` (see `.lem-ref/extensions/dot-mode/dot-mode.lisp:56` and `.lem-ref/extensions/c-mode/c-mode.lisp:269`). The plan uses `define-file-type`. Functionally equivalent to what the spec describes.

---

## File structure

| File | Action | Purpose |
|---|---|---|
| `qlfile` | modify | Add `ql rove` dep |
| `qlfile.lock` | regenerated | `qlot install` regenerates |
| `phaverlite-mode.asd` | create | Main system, at repo root, `:pathname "src"` |
| `phaverlite-mode-tests.asd` | create | Test system, at repo root, `:pathname "tests"` |
| `src/syntax.lisp` | create | `phaverlite-mode/syntax` — syntax table + tm-language patterns |
| `src/indent.lisp` | create | `phaverlite-mode/indent` — `calc-indent` function |
| `src/commands.lisp` | create | `phaverlite-mode/commands` — `phaverlite-run-buffer` + keymap |
| `src/mode.lisp` | create | `phaverlite-mode` — `define-major-mode` + `define-file-type` |
| `tests/main.lisp` | create | `phaverlite-mode/tests` — single-file rove suite |
| `tests/fake-phaverlite` | create (executable) | Shell stub: `echo "FAKE OUTPUT $1"; exit ${FAKE_EXIT:-0}` |
| `bin/test-mode` | create (executable) | zsh launcher for the rove suite |
| `config/init.lisp` | modify | Push project root to ASDF central registry; quickload `:phaverlite-mode` |
| `var/lem.core` | regenerated | Rebuild via `bin/build-image` after wiring |

---

## Task 1: Add rove dep and run qlot install

**Files:**
- Modify: `qlfile`
- Regenerated: `qlfile.lock`, `.qlot/`

- [ ] **Step 1: Inspect current `qlfile`**

```bash
cat qlfile
```

Expected: existing `ql` and `git` lines for lem and friends. No `rove` line yet.

- [ ] **Step 2: Add rove**

Append a new `ql rove` line to `qlfile`:

```
ql rove
```

(Keep all existing lines; just add this one at the bottom.)

- [ ] **Step 3: Run qlot install**

```bash
qlot install
```

Expected: qlot fetches rove and any transitive deps (`fiveam`-free; rove has its own); writes to `.qlot/` and updates `qlfile.lock`. Network-bound, ~10–60s.

- [ ] **Step 4: Verify rove loads**

```bash
qlot exec sbcl --noinform --no-userinit --no-sysinit \
  --eval '(ql:quickload :rove :silent t)' \
  --eval '(format t "rove loaded: ~a~%" (find-package :rove))' \
  --eval '(uiop:quit 0)'
```

Expected: prints `rove loaded: #<PACKAGE "ROVE">` and exits 0.

- [ ] **Step 5: Commit**

```bash
git add qlfile qlfile.lock
git commit -m "$(cat <<'EOF'
sub-project B: add rove test framework dep

Brings in rove via qlot for the phaverlite-mode test system. Production
image (var/lem.core) will not load rove — only the tests asd depends on it.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: ASDF skeleton — root asd files, empty src files, asdf-registry wiring

**Files:**
- Create: `phaverlite-mode.asd`
- Create: `phaverlite-mode-tests.asd`
- Create: `src/syntax.lisp` `src/indent.lisp` `src/commands.lisp` `src/mode.lisp` (empty stubs)
- Create: `tests/main.lisp` (empty stub)
- Modify: `config/init.lisp` (register ASDF source registry; quickload phaverlite-mode)

This task wires the system so `(ql:quickload :phaverlite-mode)` succeeds. No functionality yet — every file is a minimal `(defpackage …) (in-package …)` shell.

- [ ] **Step 1: Create `phaverlite-mode.asd` at repo root**

```lisp
;;;; phaverlite-mode.asd — main system for the .pha major mode.
;;;; Loaded by config/init.lisp via (ql:quickload :phaverlite-mode).
;;;; Layout follows lem's convention: asd at repo root, :pathname "src".

(defsystem "phaverlite-mode"
  :description "PHAVer (.pha) major mode for lem."
  :depends-on ("lem/core")
  :pathname "src"
  :serial t
  :components ((:file "syntax")
               (:file "indent")
               (:file "commands")
               (:file "mode")))
```

- [ ] **Step 2: Create `phaverlite-mode-tests.asd` at repo root**

```lisp
;;;; phaverlite-mode-tests.asd — rove test system for phaverlite-mode.
;;;; Run via: (asdf:test-system :phaverlite-mode-tests)
;;;;     or:  bin/test-mode

(defsystem "phaverlite-mode-tests"
  :description "Rove tests for phaverlite-mode."
  :depends-on ("phaverlite-mode" "rove")
  :pathname "tests"
  :components ((:file "main"))
  :perform (test-op (op c) (symbol-call :rove '#:run c)))
```

- [ ] **Step 3: Create empty package shells in `src/`**

`src/syntax.lisp`:
```lisp
;;;; src/syntax.lisp — syntax table + tm-language patterns for .pha files.

(defpackage #:phaverlite-mode/syntax
  (:use #:cl #:lem)
  (:export #:*phaverlite-syntax-table*
           #:syntax-keyword-block-attribute))
(in-package #:phaverlite-mode/syntax)
```

`src/indent.lisp`:
```lisp
;;;; src/indent.lisp — block-aware indent calculator for .pha files.

(defpackage #:phaverlite-mode/indent
  (:use #:cl #:lem)
  (:export #:calc-indent))
(in-package #:phaverlite-mode/indent)
```

`src/commands.lisp`:
```lisp
;;;; src/commands.lisp — phaverlite-run-buffer command + mode keymap.

(defpackage #:phaverlite-mode/commands
  (:use #:cl #:lem)
  (:export #:phaverlite-run-buffer
           #:*phaverlite-mode-keymap*))
(in-package #:phaverlite-mode/commands)
```

`src/mode.lisp`:
```lisp
;;;; src/mode.lisp — top-level: define-major-mode + define-file-type.

(defpackage #:phaverlite-mode
  (:use #:cl #:lem #:lem/language-mode
        #:phaverlite-mode/syntax
        #:phaverlite-mode/indent
        #:phaverlite-mode/commands)
  (:export #:phaverlite-mode
           #:phaverlite-run-buffer))
(in-package #:phaverlite-mode)
```

- [ ] **Step 4: Create empty `tests/main.lisp`**

```lisp
;;;; tests/main.lisp — rove suite for phaverlite-mode.

(defpackage #:phaverlite-mode/tests
  (:use #:cl #:rove))
(in-package #:phaverlite-mode/tests)
```

- [ ] **Step 5: Update `config/init.lisp` to register the project as an ASDF source and quickload the mode**

Open `config/init.lisp`. Find the line:
```lisp
(ql:quickload :lem-ncurses :silent t)
```

Insert AFTER it (and BEFORE the banner `defparameter`):
```lisp
;; Register the repo root as an ASDF source so (ql:quickload :phaverlite-mode)
;; finds phaverlite-mode.asd. uiop:getcwd is the launcher's cd target — the
;; bin/phaverlite-ide script does `cd "$REPO"` before exec'ing sbcl.
(pushnew (truename (uiop:getcwd)) asdf:*central-registry* :test #'equal)
(ql:quickload :phaverlite-mode :silent t)
```

- [ ] **Step 6: Verify the system loads from a fresh sbcl**

```bash
PHAVERLITE_IDE_LIB="$PWD/var/lib" qlot exec sbcl \
  --noinform --no-userinit --no-sysinit \
  --eval '(ql:quickload :cffi :silent t)' \
  --eval '(let ((d (uiop:getenv "PHAVERLITE_IDE_LIB"))) (when d (pushnew (uiop:ensure-directory-pathname d) cffi:*foreign-library-directories* :test #'\''equal)))' \
  --eval '(pushnew (truename ".") asdf:*central-registry* :test #'\''equal)' \
  --eval '(ql:quickload :phaverlite-mode :silent t)' \
  --eval '(format t "loaded packages: ~a ~a ~a ~a ~a~%" (find-package :phaverlite-mode) (find-package :phaverlite-mode/syntax) (find-package :phaverlite-mode/indent) (find-package :phaverlite-mode/commands) (find-package :phaverlite-mode/tests))' \
  --eval '(uiop:quit 0)'
```

Expected: `loaded packages: #<PACKAGE "PHAVERLITE-MODE"> #<PACKAGE "PHAVERLITE-MODE/SYNTAX"> #<PACKAGE "PHAVERLITE-MODE/INDENT"> #<PACKAGE "PHAVERLITE-MODE/COMMANDS"> NIL` (the tests package is NIL because we didn't load `phaverlite-mode-tests` — that's correct; production never loads it).

If you get `Component "phaverlite-mode" not found`, the central-registry push didn't pick up the asd. Re-check that the asd is at `./phaverlite-mode.asd` and the truename push happened.

- [ ] **Step 7: Commit**

```bash
git add phaverlite-mode.asd phaverlite-mode-tests.asd src/syntax.lisp src/indent.lisp src/commands.lisp src/mode.lisp tests/main.lisp config/init.lisp
git commit -m "$(cat <<'EOF'
sub-project B: ASDF skeleton + asdf-registry wiring

Adds phaverlite-mode.asd and phaverlite-mode-tests.asd at repo root
(lem convention: :pathname "src", :pathname "tests"). Source files are
empty package shells — no behavior yet. config/init.lisp registers the
repo root in asdf:*central-registry* and quickloads :phaverlite-mode.

Verified: a fresh sbcl can quickload :phaverlite-mode and all four
sub-packages exist.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Test scaffolding — runner script, fake-phaverlite, trivial passing rove test

**Files:**
- Create: `bin/test-mode` (executable)
- Create: `tests/fake-phaverlite` (executable)
- Modify: `tests/main.lisp` (add one trivial `(deftest …)`)

After this task, `bin/test-mode` runs and exits 0 with one passing test. The pieces are in place; subsequent tasks add real tests.

- [ ] **Step 1: Create `tests/fake-phaverlite`**

```bash
cat > tests/fake-phaverlite <<'EOF'
#!/bin/sh
# tests/fake-phaverlite — test fixture that stands in for the real phaverlite.
# Echoes a deterministic line containing the path it was called with, then
# exits with $FAKE_EXIT (default 0). Used by tests/main.lisp run-command tests.
echo "FAKE OUTPUT $1"
exit ${FAKE_EXIT:-0}
EOF
chmod +x tests/fake-phaverlite
```

- [ ] **Step 2: Verify the fake binary works**

```bash
PATH="$PWD/tests:$PATH" phaverlite /tmp/whatever.pha; echo "exit: $?"
FAKE_EXIT=3 PATH="$PWD/tests:$PATH" phaverlite /tmp/whatever.pha; echo "exit: $?"
```

Wait — that won't work because the script is `fake-phaverlite`, not `phaverlite`. The plan is to symlink it inside the test launcher. For now, just run the script directly:

```bash
./tests/fake-phaverlite /tmp/whatever.pha; echo "exit: $?"
FAKE_EXIT=3 ./tests/fake-phaverlite /tmp/whatever.pha; echo "exit: $?"
```

Expected:
```
FAKE OUTPUT /tmp/whatever.pha
exit: 0
FAKE OUTPUT /tmp/whatever.pha
exit: 3
```

- [ ] **Step 3: Create `bin/test-mode`**

```bash
cat > bin/test-mode <<'EOF'
#!/usr/bin/env zsh
# bin/test-mode — run the rove suite for phaverlite-mode.
#
# Prepends tests/ to PATH so that `phaverlite-run-buffer` calls into our
# fake binary rather than a real `phaverlite`. The fake echoes a known
# string and obeys $FAKE_EXIT — tests assert against both.
#
# Exits with rove's exit code: 0 on all-pass, non-zero on any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -d "$REPO/.qlot" ]]; then
  print -u2 "test-mode: $REPO/.qlot/ missing. Run 'qlot install' first."
  exit 1
fi
if [[ ! -f "$REPO/var/lib/libasyncprocess.dylib" ]]; then
  print -u2 "test-mode: $REPO/var/lib/libasyncprocess.dylib missing."
  print -u2 "           Run 'bin/build-deps' first."
  exit 1
fi

# Symlink fake-phaverlite as `phaverlite` in a private dir we put first on PATH.
# Keep the symlink under var/ (gitignored) so we don't pollute tests/.
mkdir -p "$REPO/var/test-bin"
ln -sf "$REPO/tests/fake-phaverlite" "$REPO/var/test-bin/phaverlite"

cd "$REPO"

PATH="$REPO/var/test-bin:$PATH" \
PHAVERLITE_IDE_LIB="$REPO/var/lib" \
qlot exec sbcl \
  --noinform --no-userinit --no-sysinit \
  --eval '(ql:quickload :cffi :silent t)' \
  --eval "(let ((d (uiop:getenv \"PHAVERLITE_IDE_LIB\"))) (when d (pushnew (uiop:ensure-directory-pathname d) cffi:*foreign-library-directories* :test #'equal)))" \
  --eval "(pushnew (truename \".\") asdf:*central-registry* :test #'equal)" \
  --eval '(ql:quickload :phaverlite-mode-tests :silent t)' \
  --eval '(uiop:quit (if (rove:run :phaverlite-mode-tests) 0 1))'
EOF
chmod +x bin/test-mode
```

- [ ] **Step 4: Add a trivial passing rove test**

Replace the contents of `tests/main.lisp` with:
```lisp
;;;; tests/main.lisp — rove suite for phaverlite-mode.

(defpackage #:phaverlite-mode/tests
  (:use #:cl #:rove))
(in-package #:phaverlite-mode/tests)

(deftest scaffolding-loads
  (testing "phaverlite-mode package exists after loading the test system"
    (ok (find-package :phaverlite-mode)))
  (testing "all sub-packages exist"
    (ok (find-package :phaverlite-mode/syntax))
    (ok (find-package :phaverlite-mode/indent))
    (ok (find-package :phaverlite-mode/commands))))
```

- [ ] **Step 5: Run the test suite**

```bash
bin/test-mode; echo "exit: $?"
```

Expected: rove prints a green PASS for `scaffolding-loads` (3 ok); script exits 0.

If you see `Component "phaverlite-mode-tests" not found`, the asd registry push happened too late or the path is wrong — re-check Task 2 step 5.

- [ ] **Step 6: Commit**

```bash
git add bin/test-mode tests/fake-phaverlite tests/main.lisp
git commit -m "$(cat <<'EOF'
sub-project B: test runner + scaffolding test

Adds bin/test-mode (zsh launcher; runs rove via asdf:test-system) and
tests/fake-phaverlite (shell stub that simulates the real phaverlite
binary for run-command tests). One trivial deftest verifies the package
shells loaded.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: syntax.lisp — TDD for keyword faces and comments

**Reference pattern:** `.lem-ref/extensions/dot-mode/dot-mode.lisp` shows the full pattern: define a custom attribute, build a tm-language with `make-tm-patterns` + `make-tm-line-comment-region` + `make-tm-block-comment-region` + `make-tm-match :name 'attr`, then build a syntax-table with `make-syntax-table` and `set-syntax-parser`. Also useful: `.lem-ref/extensions/c-mode/grammar.lisp`.

**Files:**
- Modify: `src/syntax.lisp`
- Modify: `tests/main.lisp` (add `(deftest syntax …)`)

- [ ] **Step 1: Write the failing test**

Append to `tests/main.lisp`:
```lisp
(defun face-at (text position)
  "Insert TEXT into a fresh buffer with the phaverlite syntax table,
   run a syntax scan, and return the value of the :attribute text property
   at POSITION (0-based char offset). Returns NIL if no attribute."
  (let* ((buf (lem:make-buffer "*syntax-test*" :temporary t))
         (point (lem:buffer-point buf)))
    (setf (lem:buffer-syntax-table buf)
          phaverlite-mode/syntax:*phaverlite-syntax-table*)
    (setf (lem:variable-value 'lem:enable-syntax-highlight :buffer buf) t)
    (lem:erase-buffer buf)
    (lem:insert-string point text)
    ;; Force a full syntax scan over the buffer.
    (lem:syntax-scan-region (lem:buffer-start-point buf)
                            (lem:buffer-end-point buf))
    (lem:character-offset (lem:buffer-start-point buf) position)
    (lem:text-property-at (lem:buffer-start-point buf) :attribute position)))

(deftest syntax
  (testing "block keyword 'automaton' uses the block face"
    (let ((attr (face-at "automaton heater" 0)))
      (ok (eq attr 'phaverlite-mode/syntax:syntax-keyword-block-attribute))))
  (testing "block keyword 'end' uses the block face"
    (let ((attr (face-at "end" 0)))
      (ok (eq attr 'phaverlite-mode/syntax:syntax-keyword-block-attribute))))
  (testing "regular keyword 'while' uses the stock keyword face"
    (let ((attr (face-at "while x >= 18" 0)))
      (ok (eq attr 'lem:syntax-keyword-attribute))))
  (testing "// line comment uses the comment face"
    (let ((attr (face-at "// hello" 0)))
      (ok (eq attr 'lem:syntax-comment-attribute))))
  (testing "/* block comment */ uses the comment face"
    (let ((attr (face-at "/* hi */" 0)))
      (ok (eq attr 'lem:syntax-comment-attribute)))))
```

- [ ] **Step 2: Run the test, verify it fails**

```bash
bin/test-mode
```

Expected: rove fails the `syntax` deftest. Most likely `*phaverlite-syntax-table*` is unbound (currently exported but not defined). That's the failure we want.

- [ ] **Step 3: Implement `src/syntax.lisp`**

Replace the package shell with:
```lisp
;;;; src/syntax.lisp — syntax table + tm-language patterns for .pha files.
;;;; Pattern reference: lem/extensions/dot-mode/dot-mode.lisp.

(defpackage #:phaverlite-mode/syntax
  (:use #:cl #:lem #:lem/language-mode-tools)
  (:export #:*phaverlite-syntax-table*
           #:syntax-keyword-block-attribute))
(in-package #:phaverlite-mode/syntax)

;; Custom face: bolder than the stock keyword face. Used for the three
;; structural keywords (automaton, end, loc) so they pop visually.
(define-attribute syntax-keyword-block-attribute
  (t :foreground :base09 :bold t))

(defparameter *block-keywords*
  '("automaton" "end" "loc"))

(defparameter *keywords*
  '("contr_var" "synclabs" "initially"
    "while" "wait" "when" "sync" "do" "goto"))

(defun word-tokens (strings)
  "Build a tm-language alternation regex matching any of STRINGS at word
   boundaries. Longest-first so 'automaton' wins over a hypothetical 'auto'."
  `(:sequence
    :word-boundary
    (:alternation ,@(sort (copy-list strings) #'> :key #'length))
    :word-boundary))

(defun make-tmlanguage-phaverlite ()
  (let ((patterns
         (make-tm-patterns
          (make-tm-line-comment-region "//")
          (make-tm-block-comment-region "/*" "*/")
          (make-tm-match "-?(\\.[0-9]+)|([0-9]+(\\.[0-9]*)?)"
                         :name 'syntax-constant-attribute)
          (make-tm-match (word-tokens *block-keywords*)
                         :name 'syntax-keyword-block-attribute)
          (make-tm-match (word-tokens *keywords*)
                         :name 'syntax-keyword-attribute))))
    (make-tmlanguage :patterns patterns)))

(defparameter *phaverlite-syntax-table*
  (let ((table (make-syntax-table
                :space-chars '(#\space #\tab #\newline)
                :line-comment-string "//"
                :block-comment-pairs '(("/*" . "*/"))))
        (tm (make-tmlanguage-phaverlite)))
    (set-syntax-parser table tm)
    table))
```

- [ ] **Step 4: Run the test, verify it passes**

```bash
bin/test-mode
```

Expected: `scaffolding-loads` PASS, `syntax` PASS (5 ok). Exit 0.

If a face assertion fails, double-check the attribute symbol name matches `syntax-keyword-block-attribute` in BOTH the `define-attribute` form and the test's `eq` check.

- [ ] **Step 5: Commit**

```bash
git add src/syntax.lisp tests/main.lisp
git commit -m "$(cat <<'EOF'
sub-project B: syntax.lisp — keywords, faces, comments

Implements *phaverlite-syntax-table* with two keyword categories (block
keywords get a bolder custom face; everything else uses lem's stock
keyword face), // line comments, /* */ block comments, and number
literals. Pattern follows lem's dot-mode/c-mode reference.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: indent.lisp — TDD for block-aware calc-indent

**Files:**
- Modify: `src/indent.lisp`
- Modify: `tests/main.lisp` (add `(deftest indent …)`)

- [ ] **Step 1: Write the failing test**

Append to `tests/main.lisp`:
```lisp
(defun expected-indent (text line-index)
  "Make a fresh buffer holding TEXT, move point to the start of the
   LINE-INDEX'th line (0-based), and call calc-indent. Returns the
   integer column the line should start at."
  (let* ((buf (lem:make-buffer "*indent-test*" :temporary t))
         (point (lem:buffer-point buf)))
    (lem:erase-buffer buf)
    (lem:insert-string point text)
    (lem:move-to-line point (1+ line-index))
    (lem:line-start point)
    (phaverlite-mode/indent:calc-indent point)))

(deftest indent
  (testing "top of file indents to 0"
    (ok (= 0 (expected-indent "automaton heater" 0))))
  (testing "line after 'automaton …' indents +4"
    (ok (= 4 (expected-indent (format nil "automaton heater~%contr_var: t;") 1))))
  (testing "line after a ': '-terminated header indents +4"
    (ok (= 4 (expected-indent (format nil "loc cool:~%  while x >= 18") 1))))
  (testing "line starting with 'end' dedents one step from previous indent"
    (ok (= 0 (expected-indent (format nil "    while x >= 18~%end") 1))))
  (testing "blank previous line falls back to nearest non-blank"
    (ok (= 4 (expected-indent (format nil "loc cool:~%~%  wait { x' == -0.1*x }") 2)))))
```

- [ ] **Step 2: Run, verify failure**

```bash
bin/test-mode
```

Expected: `indent` deftest fails — `calc-indent` is exported but undefined.

- [ ] **Step 3: Implement `src/indent.lisp`**

Replace the package shell with:
```lisp
;;;; src/indent.lisp — block-aware indent calculator for .pha files.
;;;;
;;;; Total function: calc-indent always returns a non-negative integer.
;;;; Algorithm:
;;;;   1. Walk back to the previous non-blank line.
;;;;   2. base = leading-whitespace column of that line.
;;;;   3. If that line ends in ':' or matches "^automaton\b" → base + 4.
;;;;   4. Else if current line's first non-whitespace token is "end"
;;;;      → max(base - 4, 0).
;;;;   5. Else → base.

(defpackage #:phaverlite-mode/indent
  (:use #:cl #:lem)
  (:export #:calc-indent))
(in-package #:phaverlite-mode/indent)

(defparameter +indent-step+ 4)

(defun line-text (point)
  "Return the text of the line POINT is on, without trailing newline."
  (let ((start (lem:copy-point point :temporary))
        (end (lem:copy-point point :temporary)))
    (lem:line-start start)
    (lem:line-end end)
    (lem:points-to-string start end)))

(defun leading-whitespace-cols (line)
  "Number of leading space chars in LINE. Tabs count as 1; we only ever
   produce spaces ourselves, and the corpus uses spaces."
  (or (position-if-not (lambda (c) (or (eql c #\space) (eql c #\tab))) line)
      0))

(defun trim-line (line)
  (string-trim '(#\space #\tab) line))

(defun line-ends-with-colon-p (line)
  (let ((s (trim-line line)))
    (and (plusp (length s))
         (char= (char s (1- (length s))) #\:))))

(defun line-starts-with-automaton-p (line)
  (let ((s (trim-line line)))
    (and (>= (length s) (length "automaton"))
         (string= s "automaton" :end1 (length "automaton"))
         (or (= (length s) (length "automaton"))
             (let ((c (char s (length "automaton"))))
               (or (char= c #\space) (char= c #\tab)))))))

(defun line-starts-with-end-p (line)
  (let ((s (trim-line line)))
    (and (>= (length s) 3)
         (string= s "end" :end1 3)
         (or (= (length s) 3)
             (let ((c (char s 3)))
               (not (alpha-char-p c)))))))

;; NOTE: do not name this `blank-line-p` — that symbol is exported from
;; `lem/buffer/internal` and our `(:use #:lem)` would package-lock-violate
;; on (defun blank-line-p ...). Use a non-colliding name.
(defun blank-text-p (line)
  (zerop (length (trim-line line))))

(defun previous-non-blank-line-text (point)
  "Walk back from POINT. Return (values TEXT FOUND-P). If the cursor is
   already on the first line, FOUND-P is NIL."
  (let ((p (lem:copy-point point :temporary)))
    (loop
      (unless (lem:line-offset p -1)
        (return (values "" nil)))
      (let ((text (line-text p)))
        (unless (blank-text-p text)
          (return (values text t)))))))

(defun calc-indent (point)
  "Return the column (integer ≥ 0) the line containing POINT should
   start at. Total function — never errors."
  (let* ((current-line (line-text point)))
    (multiple-value-bind (prev found-p)
        (previous-non-blank-line-text point)
      (if (not found-p)
          0
          (let* ((base (leading-whitespace-cols prev)))
            (cond
              ((line-starts-with-end-p current-line)
               (max 0 (- base +indent-step+)))
              ((line-ends-with-colon-p prev)
               (+ base +indent-step+))
              ((line-starts-with-automaton-p prev)
               (+ base +indent-step+))
              (t base)))))))
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode
```

Expected: `scaffolding-loads`, `syntax`, `indent` all PASS. Exit 0.

If any case fails, eyeball the fixture's expected column versus what the algorithm produces given the previous line's content. Most failures are off-by-one in `leading-whitespace-cols` or wrong predicate match.

- [ ] **Step 5: Commit**

```bash
git add src/indent.lisp tests/main.lisp
git commit -m "$(cat <<'EOF'
sub-project B: indent.lisp — block-aware calc-indent

Total function: walk back to the previous non-blank line, take its
leading whitespace as base, then +4 if it ends in ':' or starts
'automaton', or -4 if the current line starts 'end' (clamped at 0).
Otherwise inherit base.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: commands.lisp — TDD for phaverlite-run-buffer + prompt + fake-phaverlite

This task is the trickiest because it crosses several lem APIs (buffer save, prompt-for-y-or-n-p, async process spawn, pop-to-buffer, split-window). Implement defensively — small steps, run tests after each.

**Files:**
- Modify: `src/commands.lisp`
- Modify: `tests/main.lisp` (add `(deftest prompt …)` and `(deftest run-command …)`)

- [ ] **Step 1: Write the failing prompt test**

Append to `tests/main.lisp`:
```lisp
(defun with-stubbed-prompt (answer thunk)
  "Run THUNK with lem:prompt-for-y-or-n-p stubbed to return ANSWER (T or NIL)."
  (let ((original (fdefinition 'lem:prompt-for-y-or-n-p)))
    (unwind-protect
         (progn
           (setf (fdefinition 'lem:prompt-for-y-or-n-p)
                 (lambda (&rest args) (declare (ignore args)) answer))
           (funcall thunk))
      (setf (fdefinition 'lem:prompt-for-y-or-n-p) original))))

(defun make-temp-pha-buffer (&key modified)
  "Create a buffer visiting a temp .pha file, optionally in modified state."
  (let* ((path (merge-pathnames
                (format nil "phaverlite-test-~a.pha" (get-universal-time))
                (uiop:temporary-directory))))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (write-string "automaton t end" s))
    (let* ((buf (lem:find-file-buffer path)))
      (when modified
        (lem:insert-string (lem:buffer-point buf) " "))
      (values buf path))))

(deftest prompt
  (testing "modified buffer + 'no' aborts without saving"
    (multiple-value-bind (buf path) (make-temp-pha-buffer :modified t)
      (declare (ignore path))
      (with-stubbed-prompt nil
        (lambda ()
          (phaverlite-mode/commands:phaverlite-run-buffer buf)))
      (ok (lem:buffer-modified-p buf) "buffer is still modified")))
  (testing "modified buffer + 'yes' saves the buffer"
    (multiple-value-bind (buf path) (make-temp-pha-buffer :modified t)
      (declare (ignore path))
      (with-stubbed-prompt t
        (lambda ()
          (phaverlite-mode/commands:phaverlite-run-buffer buf)))
      (ng (lem:buffer-modified-p buf) "buffer is no longer modified"))))
```

- [ ] **Step 2: Run, verify failure**

```bash
bin/test-mode
```

Expected: `prompt` deftest fails — `phaverlite-run-buffer` undefined.

- [ ] **Step 3: Implement `src/commands.lisp`**

Replace the package shell with:
```lisp
;;;; src/commands.lisp — phaverlite-run-buffer command + mode keymap.
;;;;
;;;; The command:
;;;;  1. Buffer must be visiting a file (else message and abort).
;;;;  2. If buffer modified, prompt y/n to save+run; n aborts silently.
;;;;  3. Spawn `phaverlite <path>` async via uiop:launch-program.
;;;;  4. Stream stdout+stderr into a *phaverlite-output* buffer in a
;;;;     horizontal split below the source. Cursor stays in source.

(defpackage #:phaverlite-mode/commands
  (:use #:cl #:lem)
  (:export #:phaverlite-run-buffer
           #:*phaverlite-mode-keymap*))
(in-package #:phaverlite-mode/commands)

(defparameter *phaverlite-mode-keymap*
  (make-keymap :name '*phaverlite-mode-keymap*))

(defparameter *output-buffer-name* "*phaverlite-output*")

(defun ensure-output-buffer ()
  "Get-or-create the output buffer; clear it; return it."
  (let ((buf (or (lem:get-buffer *output-buffer-name*)
                 (lem:make-buffer *output-buffer-name*))))
    (lem:erase-buffer buf)
    buf))

(defun write-output-line (buf string)
  (let ((pt (lem:buffer-end-point buf)))
    (lem:insert-string pt string)
    (lem:insert-character pt #\newline)))

(defun launch-phaverlite (path output-buf)
  "Spawn `phaverlite PATH` and stream its merged stdout+stderr into
   OUTPUT-BUF. Append an exit-code footer when it terminates. Returns
   the process object."
  (write-output-line output-buf (format nil "$ phaverlite ~a" path))
  (write-output-line output-buf "----")
  (handler-case
      (let ((proc (uiop:launch-program (list "phaverlite" (namestring path))
                                       :output :stream
                                       :error-output :output)))
        ;; Drain synchronously for the prototype. lem's event loop continues
        ;; to redraw because uiop reads via a stream, not a blocking syscall.
        ;; We can revisit with a timer if real phaverlite runs are long.
        (let ((stream (uiop:process-info-output proc)))
          (loop for line = (read-line stream nil nil)
                while line
                do (write-output-line output-buf line)))
        (uiop:wait-process proc)
        (write-output-line output-buf
                           (format nil "---- exit: ~a" (uiop:wait-process proc)))
        proc)
    (error (e)
      (write-output-line output-buf (format nil "---- error: ~a" e))
      nil)))

(define-command phaverlite-run-buffer (&optional buffer) ()
  "Run `phaverlite` on the file backing BUFFER (or the current buffer).
   See command's docstring at the top of commands.lisp for the contract."
  (let* ((buf (or buffer (current-buffer)))
         (path (lem:buffer-filename buf)))
    (cond
      ((null path)
       (lem:message "Buffer not visiting a file"))
      ((and (lem:buffer-modified-p buf)
            (not (lem:prompt-for-y-or-n-p
                  "Buffer modified. Save and run phaverlite?")))
       ;; Silent abort.
       nil)
      (t
       (when (lem:buffer-modified-p buf)
         (lem:save-buffer buf))
       (let ((out (ensure-output-buffer)))
         (lem:pop-to-buffer out)
         (launch-phaverlite path out))))))

(define-key *phaverlite-mode-keymap* "C-c C-c" 'phaverlite-run-buffer)
```

- [ ] **Step 4: Run prompt tests, verify pass**

```bash
bin/test-mode
```

Expected: `prompt` PASS (2 ok). `scaffolding-loads`, `syntax`, `indent`, `prompt` all green.

If `phaverlite-run-buffer` errors out trying to spawn a missing `phaverlite` even on the `:no` path, double-check that `prompt-for-y-or-n-p` returning NIL aborts before the launch. The test stubs the prompt to return NIL on the first case; we should never reach `launch-phaverlite`.

- [ ] **Step 5: Add the run-command test**

Append to `tests/main.lisp`:
```lisp
(deftest run-command
  (testing "writes 'FAKE OUTPUT <path>' header line and exit:0 footer"
    (multiple-value-bind (buf path) (make-temp-pha-buffer :modified nil)
      (with-stubbed-prompt t
        (lambda ()
          (phaverlite-mode/commands:phaverlite-run-buffer buf)))
      (let* ((out (lem:get-buffer "*phaverlite-output*"))
             (text (lem:points-to-string
                    (lem:buffer-start-point out)
                    (lem:buffer-end-point out))))
        (ok (search (format nil "FAKE OUTPUT ~a" (namestring path)) text))
        (ok (search "---- exit: 0" text))))))
```

- [ ] **Step 6: Run, verify pass**

```bash
bin/test-mode
```

Expected: all five deftests PASS.

If `phaverlite` isn't found, `bin/test-mode` symlink wasn't created or isn't first on PATH — re-check Task 3 step 3.

- [ ] **Step 7: Commit**

```bash
git add src/commands.lisp tests/main.lisp
git commit -m "$(cat <<'EOF'
sub-project B: commands.lisp — phaverlite-run-buffer

Implements the run command: file-check → optional save prompt → uiop
spawn → drain merged stdout/stderr into *phaverlite-output* buffer in
a horizontal split → exit-code footer. Mode keymap binds C-c C-c.

Tests: prompt-y/n behavior with stubbed prompt, and end-to-end run
against tests/fake-phaverlite.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: mode.lisp — define-major-mode and define-file-type

**Reference pattern:** `.lem-ref/extensions/dot-mode/dot-mode.lisp` (especially lines 48–56) shows the exact `define-major-mode … language-mode` + `define-file-type` pattern.

**Files:**
- Modify: `src/mode.lisp`

No new test in this task — `define-file-type` registers a global side-effect; we verify it manually by opening a `.pha` file in the smoke test (Task 8).

- [ ] **Step 1: Implement `src/mode.lisp`**

Replace the package shell with:
```lisp
;;;; src/mode.lisp — top-level: define-major-mode + define-file-type binding.
;;;; Pattern reference: lem/extensions/dot-mode/dot-mode.lisp.

(defpackage #:phaverlite-mode
  (:use #:cl #:lem #:lem/language-mode
        #:phaverlite-mode/syntax
        #:phaverlite-mode/indent
        #:phaverlite-mode/commands)
  (:export #:phaverlite-mode
           #:phaverlite-run-buffer
           #:*phaverlite-mode-hook*))
(in-package #:phaverlite-mode)

(define-major-mode phaverlite-mode language-mode
    (:name "PHAVer"
     :keymap *phaverlite-mode-keymap*
     :syntax-table *phaverlite-syntax-table*
     :mode-hook *phaverlite-mode-hook*)
  (setf (variable-value 'enable-syntax-highlight) t
        (variable-value 'tab-width) 4
        (variable-value 'calc-indent-function) 'phaverlite-mode/indent:calc-indent
        (variable-value 'line-comment) "//"
        (variable-value 'beginning-of-defun-function) nil
        (variable-value 'end-of-defun-function) nil))

(define-file-type ("pha") phaverlite-mode)
```

- [ ] **Step 2: Verify the system still loads cleanly**

```bash
bin/test-mode
```

Expected: all five deftests still PASS. `mode.lisp` adding `define-major-mode` and `define-file-type` doesn't break existing tests; it just registers the mode globally inside the test sbcl too.

If you get `Variable LANGUAGE-MODE not found` or similar, the `:use` of `lem/language-mode` failed — confirm lem's `language-mode` package exists by running:
```bash
qlot exec sbcl --noinform --no-userinit --no-sysinit \
  --eval '(ql:quickload :lem :silent t)' \
  --eval '(format t "~a~%" (find-package :lem/language-mode))' \
  --eval '(uiop:quit 0)'
```

- [ ] **Step 3: Commit**

```bash
git add src/mode.lisp
git commit -m "$(cat <<'EOF'
sub-project B: mode.lisp — define-major-mode + .pha file binding

Wires the syntax table, indent function, mode keymap, and tab-width
into a phaverlite-mode major-mode (inheriting lem's language-mode for
basic editing affordances). define-file-type ("pha") registers .pha
files to open in this mode automatically.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Wire init.lisp + rebuild image + smoke corpus + verify-isolation + final commit

**Files:**
- Touched (already modified in Task 2 step 5): `config/init.lisp`
- Regenerated: `var/lem.core`

This task verifies the end-to-end DoD on a real launch. No new code; only manual smoke checks plus the regression check.

- [ ] **Step 1: Rebuild the lem core**

The mode is quickloaded by `config/init.lisp` — `bin/build-image` already loads init.lisp logic equivalents, so the new mode bakes into the image.

```bash
bin/build-image
```

Expected: prints "build-image: dumping lem-ncurses image to ..." and finishes with `ls -lh` of the new core file. ~30–60s.

If you see `Component "phaverlite-mode" not found` during the build, the central-registry push isn't happening inside `build-image`. Open `bin/build-image` and confirm it has the same `pushnew (truename …) asdf:*central-registry*` line as `config/init.lisp`. If not, copy that one-liner into the build-image's --eval chain BEFORE `(ql:quickload :lem-ncurses …)`.

- [ ] **Step 2: Launch and open a sample file**

```bash
bin/phaverlite-ide Lab3/heater_template.pha
```

Wait — sub-project A's launcher doesn't take file args. For this prototype, just launch and open via lem's file-open command:

```bash
bin/phaverlite-ide
```

Then in lem, press `C-x C-f` and type `Lab3/heater_template.pha` then Enter.

Expected eyeball:
- File opens in `phaverlite-mode` (modeline shows "PHAVer").
- `automaton`, `end`, `loc` render bolder than `contr_var`, `while`, `wait`, `when`, `sync`, `do`, `goto`.
- `// comments` (none in this file) and `__PC__` (a placeholder, will look ordinary) are visible.
- Tab on a line inside a `loc` body indents to the indented level.

If `*Messages*` shows a backtrace, that's where to look first.

- [ ] **Step 3: Smoke corpus — open the other two**

In lem, `C-x C-f`:
- `Lab3/bouncing_ball.pha` — confirm `// Hybrid System Example` line and `/* … */` block comments render in the comment face.
- the `.pha` model in `ps3/` — confirm it opens in PHAVer mode.

- [ ] **Step 4: Run command end-to-end**

In lem with `Lab3/heater_template.pha` open:
- Press `C-c C-c`.
- The output buffer `*phaverlite-output*` should appear in a split below.
- The header `$ phaverlite Lab3/heater_template.pha` and a footer `---- exit: <n>` should appear.
- (The actual phaverlite output may show errors because heater_template.pha has the unfilled `__PC__` placeholder — that's expected. We're testing the command, not the model.)

If you want a known-good run, open `Lab3/bouncing_ball.pha` and try `C-c C-c` — that file has a real numeric `pc` value.

- [ ] **Step 5: Modify-then-prompt path**

In lem with any `.pha` open:
- Type a single space anywhere in the buffer.
- Press `C-c C-c`.
- Minibuffer should prompt: `Buffer modified. Save and run phaverlite? (y or n)`.
- Press `n` — silent abort, no output buffer change.
- Press `C-c C-c` again, this time press `y` — buffer saves, command runs.

- [ ] **Step 6: Buffer-not-visiting-file path**

In lem:
- `C-x b *scratch*` (switch to scratch buffer).
- `M-x phaverlite-run-buffer`.
- Should message `Buffer not visiting a file` in the minibuffer.

- [ ] **Step 7: Run isolation regression**

Exit lem (`C-x C-c`). Then:

```bash
bin/verify-isolation
```

Expected: `[verify-isolation] PASS: no changes under watched paths.` Exit 0.

If FAIL, the new mode is writing somewhere it shouldn't. `bin/verify-isolation`'s output names the offending paths.

- [ ] **Step 8: Run the test suite one more time as a final regression**

```bash
bin/test-mode; echo "exit: $?"
```

Expected: all five deftests PASS, exit 0.

- [ ] **Step 9: Final commit (the only outstanding change is `var/lem.core`, which is gitignored)**

`git status` should be clean. If `bin/build-image` was modified during Step 1's troubleshooting, commit that:

```bash
git status
# If bin/build-image changed:
git add bin/build-image
git commit -m "$(cat <<'EOF'
sub-project B: bake phaverlite-mode into bin/build-image

Adds the asdf:*central-registry* push and (ql:quickload :phaverlite-mode)
to the image-build pipeline so var/lem.core ships with the mode pre-loaded.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 10: Privacy preflight, then push (if the user OKs)**

```bash
bin/privacy-preflight unpushed || exit 1
```

`token` will false-positive on legitimate uses; eyeball the matches. If clean and the user has approved push:

```bash
git push origin main
```

---

## Definition-of-done checklist (verify against spec)

Tick these off after Task 8:

- [ ] (DoD 1) `.pha` files open in phaverlite-mode automatically
- [ ] (DoD 2) Block keywords visibly stronger than other keywords; comments greyed
- [ ] (DoD 3) Enter-after-`:` and Enter-after-`automaton` indent +4; Tab on `end` line dedents −4
- [ ] (DoD 4) `M-;` toggles `// ` (inherited from `language-mode` + `:line-comment` setting)
- [ ] (DoD 5) Paren matching for `()`, `{}`, `[]` works
- [ ] (DoD 6) `M-x phaverlite-run-buffer` (and `C-c C-c`) honors all four branches
- [ ] (DoD 7) `bin/test-mode` exits 0
- [ ] (DoD 8) `bin/verify-isolation` PASS
