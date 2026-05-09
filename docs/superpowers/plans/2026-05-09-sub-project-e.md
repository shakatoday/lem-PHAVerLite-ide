# Sub-project E — phaverlite-lsp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A minimal LSP server for `.pha` files providing live structural diagnostics (squiggles for unmatched braces / `automaton` without `end` / orphan `end`) and kind-aware autocomplete (static keywords + regex-scanned user symbols + dot-completion that returns automaton-methods after an automaton-IDENT and `print` after a region-IDENT).

**Architecture:** Three new ASDF systems. `phaverlite-lsp` is the standalone server (depends on `jsonrpc` + `cl-ppcre`, NO lem deps); `phaverlite-mode-lsp` is the client glue inside lem (depends on `phaverlite-mode` + `lem-lsp-mode`, one `define-language-spec` form); `phaverlite-lsp-tests` is the rove suite for the server (depends on `phaverlite-lsp` + `rove`). The server is launched on demand by `lem-lsp-mode` via `bin/phaverlite-lsp` (zsh launcher running `qlot exec sbcl --script`).

**Tech Stack:** SBCL + jsonrpc (qlot-pinned, sub-project A) + cl-ppcre (transitively present via lem) + lem-lsp-mode (built into lem) + rove for tests + zsh launcher.

**Spec:** `docs/superpowers/specs/2026-05-09-sub-project-e-design.md` — read it first.

**Key references:**
- `.qlot/dists/jsonrpc/software/jsonrpc-ref-*/main.lisp` — exports (`make-server`, `expose`, `server-listen`).
- `.qlot/dists/jsonrpc/software/jsonrpc-ref-*/server.lisp` line 57 — `server-listen` signature.
- `.qlot/dists/jsonrpc/software/jsonrpc-ref-*/transport/stdio.lisp` — `:stdio` mode is lazy-loaded by `find-mode-class`.
- `.lem-ref/extensions/lsp-mode/spec.lisp` — `register-language-spec`, `defclass spec`.
- `.lem-ref/extensions/lsp-mode/lsp-mode.lisp:1823` — `define-language-spec` macro signature.
- `.lem-ref/extensions/lsp-mode/lsp-mode.lisp:1842` — rust example: `(define-language-spec (rust-spec lem-rust-mode:rust-mode) :language-id "rust" :command '("rls") :connection-mode :stdio)`.
- `bin/phaverlite-ide` — launcher pattern to mirror in `bin/phaverlite-lsp` (env-isolated, qlot exec, `--script` style).

---

## File structure

| File | Action | Purpose |
|---|---|---|
| `phaverlite-lsp.asd` | create | Server system at repo root, `:pathname "lsp"`, depends on `jsonrpc` + `cl-ppcre`. |
| `lsp/parser.lisp` | create | Package `phaverlite-lsp/parser`. `parse-document text → list of diagnostic`. |
| `lsp/symbols.lisp` | create | Package `phaverlite-lsp/symbols`. `scan-symbols text → list of symbol-info` with kind tracking. |
| `lsp/completion.lisp` | create | Package `phaverlite-lsp/completion`. `complete-at text offset symbols → list of strings`. |
| `lsp/server.lisp` | create | Package `phaverlite-lsp/server`. JSON-RPC handlers + `run-server`. |
| `lsp/main.lisp` | create | Package `phaverlite-lsp/main`. Trivial entry: calls `run-server`. |
| `phaverlite-lsp-tests.asd` | create | Test system at repo root, `:pathname "lsp-tests"`, depends on `phaverlite-lsp` + `rove`. `:perform (test-op …)` to integrate with `asdf:test-system`. |
| `lsp-tests/main.lisp` | create | Package `phaverlite-lsp/tests`. Three deftests: `lsp-parser`, `lsp-symbols`, `lsp-completion`. |
| `bin/phaverlite-lsp` | create (executable) | zsh launcher: env-isolated, `exec qlot exec sbcl --script` style, calls `(phaverlite-lsp/main:run)`. |
| `phaverlite-mode-lsp.asd` | create | Client-glue system at repo root, `:pathname "src-lsp"`, depends on `phaverlite-mode` + `lem-lsp-mode`. |
| `src-lsp/spec.lisp` | create | Package `phaverlite-mode-lsp`. Single `define-language-spec` form. |
| `bin/test-mode` | modify | Add a SECOND `qlot exec sbcl` invocation that runs `(asdf:test-system :phaverlite-lsp-tests)`. |
| `config/init.lisp` | modify | +1 line: `(ql:quickload :phaverlite-mode-lsp :silent t)` after the existing phaverlite-mode quickload. |
| `bin/build-image` | modify | +1 quickload for `:phaverlite-mode-lsp` (mirroring the `:phaverlite-mode` line) so the image bakes the client glue. |
| `qlfile` | possibly modify | If `cl-ppcre` isn't transitively present after first quickload, add `ql cl-ppcre`. Verify on Step 1.4. |
| `var/lem.core` | regenerated | `bin/build-image` rebakes after wiring (Step 9). |

---

## Task 1: Skeleton — `phaverlite-lsp.asd` + 5 empty package shells, verify load

**Files:**
- Create: `phaverlite-lsp.asd`
- Create: `lsp/parser.lisp` `lsp/symbols.lisp` `lsp/completion.lisp` `lsp/server.lisp` `lsp/main.lisp` (empty stubs)

- [ ] **Step 1: Create `phaverlite-lsp.asd` at repo root**

```lisp
;;;; phaverlite-lsp.asd — minimal LSP server for .pha files.
;;;; Standalone system (no lem deps) — server is spawned by
;;;; lem-lsp-mode as a separate process via bin/phaverlite-lsp.
;;;; See docs/superpowers/specs/2026-05-09-sub-project-e-design.md.

(defsystem "phaverlite-lsp"
  :description "LSP server for the PHAVer (.pha) language."
  :depends-on ("jsonrpc"
               "jsonrpc/transport/stdio"
               "cl-ppcre")
  :pathname "lsp"
  :serial t
  :components ((:file "parser")
               (:file "symbols")
               (:file "completion")
               (:file "server")
               (:file "main")))
```

- [ ] **Step 2: Create empty package shells**

`lsp/parser.lisp`:
```lisp
;;;; lsp/parser.lisp — structural parser for diagnostics.

(defpackage #:phaverlite-lsp/parser
  (:use #:cl)
  (:export #:parse-document
           #:diagnostic
           #:make-diagnostic
           #:diagnostic-start-line
           #:diagnostic-start-col
           #:diagnostic-end-line
           #:diagnostic-end-col
           #:diagnostic-severity
           #:diagnostic-message))
(in-package #:phaverlite-lsp/parser)
```

`lsp/symbols.lisp`:
```lisp
;;;; lsp/symbols.lisp — regex-based symbol scanner.

(defpackage #:phaverlite-lsp/symbols
  (:use #:cl)
  (:export #:scan-symbols
           #:symbol-info
           #:make-symbol-info
           #:symbol-info-name
           #:symbol-info-kind
           #:symbol-info-line))
(in-package #:phaverlite-lsp/symbols)
```

`lsp/completion.lisp`:
```lisp
;;;; lsp/completion.lisp — keyword + symbol + kind-aware dot completion.

(defpackage #:phaverlite-lsp/completion
  (:use #:cl)
  (:import-from #:phaverlite-lsp/symbols
                #:symbol-info
                #:symbol-info-name
                #:symbol-info-kind)
  (:export #:complete-at
           #:+keywords+
           #:+automaton-methods+
           #:+region-methods+))
(in-package #:phaverlite-lsp/completion)
```

`lsp/server.lisp`:
```lisp
;;;; lsp/server.lisp — JSON-RPC lifecycle + handlers.

(defpackage #:phaverlite-lsp/server
  (:use #:cl)
  (:export #:run-server))
(in-package #:phaverlite-lsp/server)
```

`lsp/main.lisp`:
```lisp
;;;; lsp/main.lisp — script entry point.

(defpackage #:phaverlite-lsp/main
  (:use #:cl)
  (:export #:run))
(in-package #:phaverlite-lsp/main)

(defun run ()
  (phaverlite-lsp/server:run-server))
```

- [ ] **Step 3: Verify the system loads (no lem deps)**

```bash
qlot exec sbcl \
  --noinform --no-userinit --no-sysinit \
  --eval '(pushnew (truename ".") asdf:*central-registry* :test #'\''equal)' \
  --eval '(ql:quickload :phaverlite-lsp :silent t)' \
  --eval '(format t "loaded: ~a ~a ~a ~a ~a~%" (find-package :phaverlite-lsp/parser) (find-package :phaverlite-lsp/symbols) (find-package :phaverlite-lsp/completion) (find-package :phaverlite-lsp/server) (find-package :phaverlite-lsp/main))' \
  --eval '(uiop:quit 0)'
```

Expected: `loaded: #<PACKAGE "PHAVERLITE-LSP/PARSER"> #<PACKAGE "PHAVERLITE-LSP/SYMBOLS"> ...` and exit 0. NO lem load — should be much faster than test-mode (~2s vs ~10s).

If `cl-ppcre` is not found (`Component "cl-ppcre" not found`), add it to qlfile and run `qlot install`:
```bash
echo 'ql cl-ppcre' >> qlfile
qlot install
```
(re-verify with the command above).

- [ ] **Step 4: Verify existing test suite still passes**

```bash
bin/test-mode 2>&1 | tail -3
```

Expected: `All 1 test passed.` Sub-project B+C+D oks all green.

- [ ] **Step 5: Commit**

```bash
git add phaverlite-lsp.asd lsp/parser.lisp lsp/symbols.lisp lsp/completion.lisp lsp/server.lisp lsp/main.lisp
# If qlfile was modified:
git add qlfile qlfile.lock 2>/dev/null || true
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project E: skeleton — phaverlite-lsp.asd + empty package shells

Standalone LSP server system at repo root with five empty package
shells (parser, symbols, completion, server, main). Depends on
jsonrpc + jsonrpc/transport/stdio + cl-ppcre — no lem deps so the
server can load in its own sbcl without paying for lem.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Test system + bin/test-mode extension + trivial passing test

**Files:**
- Create: `phaverlite-lsp-tests.asd`
- Create: `lsp-tests/main.lisp`
- Modify: `bin/test-mode`

- [ ] **Step 1: Create `phaverlite-lsp-tests.asd` at repo root**

```lisp
;;;; phaverlite-lsp-tests.asd — rove test system for phaverlite-lsp.
;;;; Run via: bin/test-mode (which now invokes BOTH suites in
;;;; separate sbcls), or directly via:
;;;;   (asdf:test-system :phaverlite-lsp-tests)

(defsystem "phaverlite-lsp-tests"
  :description "Rove tests for phaverlite-lsp (server-side)."
  :depends-on ("phaverlite-lsp" "rove")
  :pathname "lsp-tests"
  :components ((:file "main"))
  :perform (test-op (op c) (symbol-call :rove '#:run c)))
```

- [ ] **Step 2: Create empty `lsp-tests/main.lisp`**

```lisp
;;;; lsp-tests/main.lisp — rove suite for phaverlite-lsp.

(defpackage #:phaverlite-lsp/tests
  (:use #:cl #:rove))
(in-package #:phaverlite-lsp/tests)

(deftest scaffolding-loads
  (testing "all phaverlite-lsp sub-packages exist"
    (ok (find-package :phaverlite-lsp/parser))
    (ok (find-package :phaverlite-lsp/symbols))
    (ok (find-package :phaverlite-lsp/completion))
    (ok (find-package :phaverlite-lsp/server))
    (ok (find-package :phaverlite-lsp/main))))
```

- [ ] **Step 3: Read the current `bin/test-mode` to find the existing test invocation**

```bash
cat bin/test-mode
```

Locate the line that runs `(asdf:test-system :phaverlite-mode-tests)` (or the equivalent rove invocation).

- [ ] **Step 4: Extend `bin/test-mode` with a second sbcl invocation**

After the existing test invocation block (and BEFORE the script's final `exit` if any), add:

```sh
# --- second suite: phaverlite-lsp-tests (server-side, no lem deps) ---
echo
echo "=== phaverlite-lsp-tests ==="
qlot exec sbcl \
  --noinform --no-userinit --no-sysinit \
  --eval '(pushnew (truename ".") asdf:*central-registry* :test #'\''equal)' \
  --eval '(ql:quickload :phaverlite-lsp-tests :silent t)' \
  --eval '(uiop:quit (if (rove:run :phaverlite-lsp-tests) 0 1))'
```

The second sbcl is intentional — the server-tests sbcl shouldn't load lem (saves ~5s). `bin/test-mode` exits 0 only if BOTH sbcl invocations succeed (because of `set -e` at the top of the script — if not present, add `set -e`).

If `bin/test-mode` doesn't have `set -e`, add it at the top so any failed sub-invocation aborts the script. Re-check the script's existing structure before editing.

- [ ] **Step 5: Run `bin/test-mode` — verify both suites pass**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: TWO summary blocks, both saying `All 1 test passed.` exit 0.

- [ ] **Step 6: Commit**

```bash
git add phaverlite-lsp-tests.asd lsp-tests/main.lisp bin/test-mode
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project E: phaverlite-lsp-tests + bin/test-mode extension

Adds the test system at repo root for the LSP server. bin/test-mode
now invokes BOTH suites sequentially in separate sbcl processes so
the server-tests sbcl doesn't pay for loading lem.

Trivial scaffolding deftest verifies all five sub-packages exist
after quickload.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: parser.lisp — TDD for `parse-document`

**Files:**
- Modify: `lsp/parser.lisp`
- Modify: `lsp-tests/main.lisp`

The parser tracks a stack of open brackets + automaton-block depth, line by line. Each closer pops the expected matching opener; mismatches and end-of-file unmatched-opens become diagnostics. Severity is always `:error` for prototype.

- [ ] **Step 1: Write the failing test**

Append to `lsp-tests/main.lisp`:

```lisp
(defun diag-fields (d)
  "Helper: return (list start-line start-col message-substring) — used by
   tests that don't care about end-line/end-col. message-substring is the
   full message; tests use search to look for keywords."
  (list (phaverlite-lsp/parser:diagnostic-start-line d)
        (phaverlite-lsp/parser:diagnostic-start-col d)
        (phaverlite-lsp/parser:diagnostic-message d)))

(deftest lsp-parser
  (testing "empty text → no diagnostics"
    (ok (null (phaverlite-lsp/parser:parse-document ""))))
  (testing "clean automaton X end → no diagnostics"
    (ok (null (phaverlite-lsp/parser:parse-document "automaton heater
end"))))
  (testing "automaton without end → one diagnostic mentioning 'end'"
    (let ((diags (phaverlite-lsp/parser:parse-document "automaton heater
contr_var: t;")))
      (ok (= 1 (length diags)))
      (let ((d (first diags)))
        (ok (eq :error (phaverlite-lsp/parser:diagnostic-severity d)))
        (ok (search "end" (phaverlite-lsp/parser:diagnostic-message d))))))
  (testing "orphan end → diagnostic mentioning 'orphan' or 'no automaton'"
    (let ((diags (phaverlite-lsp/parser:parse-document "end")))
      (ok (= 1 (length diags)))
      (let ((msg (phaverlite-lsp/parser:diagnostic-message (first diags))))
        (ok (or (search "orphan" msg) (search "no automaton" msg))))))
  (testing "unmatched { → one diagnostic at the open brace"
    (let ((diags (phaverlite-lsp/parser:parse-document "automaton x
loc l: wait { x' == 1
end")))
      (ok (= 1 (length diags)))
      (let ((msg (phaverlite-lsp/parser:diagnostic-message (first diags))))
        (ok (or (search "{" msg) (search "brace" msg))))))
  (testing "mismatched closer ({)} → diagnostic at the bad closer"
    (let ((diags (phaverlite-lsp/parser:parse-document "automaton x
loc l: wait ( foo }
end")))
      (ok (>= (length diags) 1))))
  (testing "multiple errors → multiple diagnostics"
    (let ((diags (phaverlite-lsp/parser:parse-document "automaton x
end
end")))
      (ok (>= (length diags) 1))
      ;; The second `end` is an orphan.
      )))
```

- [ ] **Step 2: Run, verify failure**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: `lsp-parser` deftest fails with `parse-document` undefined or the diagnostic struct accessor undefined.

- [ ] **Step 3: Implement `lsp/parser.lisp`**

Replace the package shell with:

```lisp
;;;; lsp/parser.lisp — structural parser for .pha diagnostics.
;;;;
;;;; Strategy: line-by-line scan. Maintain two stacks:
;;;;   - bracket-stack: each entry is (kind line col), kind ∈ {:paren :brace :bracket}
;;;;   - automaton-stack: each entry is (line col) for an open `automaton`
;;;; On bracket close: pop, check matching kind. Mismatch or empty stack → diag.
;;;; On `end` keyword at start of trimmed line: pop automaton-stack. Empty → orphan.
;;;; At EOF: any remaining stack entries are unmatched-open diagnostics.

(defpackage #:phaverlite-lsp/parser
  (:use #:cl)
  (:export #:parse-document
           #:diagnostic
           #:make-diagnostic
           #:diagnostic-start-line
           #:diagnostic-start-col
           #:diagnostic-end-line
           #:diagnostic-end-col
           #:diagnostic-severity
           #:diagnostic-message))
(in-package #:phaverlite-lsp/parser)

(defstruct diagnostic
  start-line start-col end-line end-col
  severity              ; :error | :warning
  message)

(defun bracket-kind (ch)
  "Return :paren / :brace / :bracket for an opener or closer; NIL otherwise."
  (case ch
    ((#\( #\)) :paren)
    ((#\{ #\}) :brace)
    ((#\[ #\]) :bracket)))

(defun bracket-opener-p (ch) (member ch '(#\( #\{ #\[)))
(defun bracket-closer-p (ch) (member ch '(#\) #\} #\])))

(defun line-start-token (line)
  "Return the first non-whitespace word of LINE (lowercased), or \"\" if blank."
  (let* ((trimmed (string-trim '(#\space #\tab) line))
         (sp (or (position-if (lambda (c) (or (char= c #\space) (char= c #\tab) (char= c #\:)))
                              trimmed)
                 (length trimmed))))
    (string-downcase (subseq trimmed 0 sp))))

(defun parse-document (text)
  "Return list of DIAGNOSTIC structs for TEXT. Empty list = clean."
  (let ((diags '())
        (bracket-stack '())
        (automaton-stack '())
        (line-no 0))
    (with-input-from-string (s text)
      (loop for line = (read-line s nil nil)
            while line
            do (incf line-no)
               (let ((token (line-start-token line)))
                 (cond
                   ((string= token "automaton")
                    (push (list line-no 1) automaton-stack))
                   ((string= token "end")
                    (if automaton-stack
                        (pop automaton-stack)
                        (push (make-diagnostic
                               :start-line line-no :start-col 1
                               :end-line line-no
                               :end-col (length line)
                               :severity :error
                               :message "orphan `end` (no preceding `automaton`)")
                              diags)))))
               (loop for col from 0 below (length line)
                     for ch = (char line col)
                     when (bracket-opener-p ch)
                       do (push (list (bracket-kind ch) line-no (1+ col)) bracket-stack)
                     when (bracket-closer-p ch)
                       do (cond
                            ((null bracket-stack)
                             (push (make-diagnostic
                                    :start-line line-no :start-col (1+ col)
                                    :end-line line-no :end-col (1+ col)
                                    :severity :error
                                    :message (format nil "unmatched closing `~c`" ch))
                                   diags))
                            ((not (eq (first (first bracket-stack)) (bracket-kind ch)))
                             (let ((opener (pop bracket-stack)))
                               (declare (ignore opener))
                               (push (make-diagnostic
                                      :start-line line-no :start-col (1+ col)
                                      :end-line line-no :end-col (1+ col)
                                      :severity :error
                                      :message (format nil "mismatched closing `~c`" ch))
                                     diags)))
                            (t (pop bracket-stack))))))
      ;; EOF: any remaining open brackets are unmatched.
      (dolist (entry bracket-stack)
        (destructuring-bind (kind ln col) entry
          (push (make-diagnostic
                 :start-line ln :start-col col :end-line ln :end-col col
                 :severity :error
                 :message (format nil "unmatched opening `~a` (no closer)"
                                  (case kind (:paren "(") (:brace "{") (:bracket "["))))
                diags)))
      ;; EOF: any remaining open automatons are unclosed.
      (dolist (entry automaton-stack)
        (destructuring-bind (ln col) entry
          (push (make-diagnostic
                 :start-line ln :start-col col :end-line ln :end-col col
                 :severity :error
                 :message "`automaton` without matching `end`")
                diags))))
    (nreverse diags)))
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: both suites green, including the new `lsp-parser` deftest (6 testing forms).

If a test fails because the expected message text doesn't match, adjust the test's `search` substring OR the function's `message` string — they should agree. The plan's messages are: `"orphan \`end\`..."`, `"unmatched closing \`...\`"`, `"\`automaton\` without matching \`end\`"`.

- [ ] **Step 5: Commit**

```bash
git add lsp/parser.lisp lsp-tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project E: parser.lisp — structural diagnostics

Hand-rolled line-by-line scanner that tracks two stacks: bracket
({/(/[) opens with kind, and automaton blocks. On close: check
matching kind, pop. On `end`: pop automaton stack. On EOF: any
remaining entries become unmatched-open diagnostics. Six deftest
cases cover empty text, clean automaton, automaton-without-end,
orphan-end, unmatched-brace, mismatched-closer, and multiple errors.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: symbols.lisp — TDD for `scan-symbols`

**Files:**
- Modify: `lsp/symbols.lisp`
- Modify: `lsp-tests/main.lisp`

- [ ] **Step 1: Write the failing test**

Append to `lsp-tests/main.lisp`:

```lisp
(defun symbols-of-kind (text kind)
  "Helper: return list of symbol-info names of KIND from scanning TEXT."
  (mapcar #'phaverlite-lsp/symbols:symbol-info-name
          (remove-if-not
           (lambda (s) (eq (phaverlite-lsp/symbols:symbol-info-kind s) kind))
           (phaverlite-lsp/symbols:scan-symbols text))))

(deftest lsp-symbols
  (testing "automaton sys → :automaton symbol named 'sys'"
    (ok (equal '("sys")
               (symbols-of-kind "automaton sys
end" :automaton))))
  (testing "loc cool: inside an automaton → :location"
    (ok (equal '("cool")
               (symbols-of-kind "automaton h
loc cool:
end" :location))))
  (testing "contr_var: x, y; → two :var symbols"
    (ok (equal '("x" "y")
               (symbols-of-kind "automaton h
contr_var: x, y;
end" :var))))
  (testing "synclabs: tau, tick; → two :sync symbols"
    (ok (equal '("tau" "tick")
               (symbols-of-kind "automaton h
synclabs: tau, tick;
end" :sync))))
  (testing "top-level pc := 0.5; → :scalar"
    (ok (equal '("pc")
               (symbols-of-kind "automaton h
end
pc := 0.5;" :scalar))))
  (testing "top-level bad = sys.{...} → :region"
    (ok (equal '("bad")
               (symbols-of-kind "automaton sys
end
bad = sys.{cool & x >= 20};" :region))))
  (testing "top-level reg = sys.reachable; → :region"
    (ok (member "reg"
                (symbols-of-kind "automaton sys
end
reg = sys.reachable;" :region)
                :test #'equal)))
  (testing "top-level check = sys.is_reachable(bad); → :region"
    (ok (member "check"
                (symbols-of-kind "automaton sys
end
check = sys.is_reachable(bad);" :region)
                :test #'equal)))
  (testing "user binding INSIDE automaton…end is NOT collected as user binding"
    (let ((scalars (symbols-of-kind "automaton h
foo := 99;
end" :scalar))
          (regions (symbols-of-kind "automaton h
foo := 99;
end" :region)))
      (ok (null scalars))
      (ok (null regions)))))
```

- [ ] **Step 2: Run, verify failure**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: `lsp-symbols` fails — `scan-symbols` undefined.

- [ ] **Step 3: Implement `lsp/symbols.lisp`**

Replace the package shell with:

```lisp
;;;; lsp/symbols.lisp — regex-based symbol scanner with kind tracking.

(defpackage #:phaverlite-lsp/symbols
  (:use #:cl)
  (:export #:scan-symbols
           #:symbol-info
           #:make-symbol-info
           #:symbol-info-name
           #:symbol-info-kind
           #:symbol-info-line))
(in-package #:phaverlite-lsp/symbols)

(defstruct symbol-info
  name                  ; string
  kind                  ; :keyword | :automaton | :location | :var | :sync
                        ; | :region | :scalar | :unknown
  line)                 ; 1-based

(defun trim (s)
  (string-trim '(#\space #\tab) s))

(defun split-and-trim (s separator)
  "Split S on SEPARATOR char, trim each piece, drop empties."
  (let ((parts (loop for start = 0 then (1+ end)
                     for end = (position separator s :start start)
                     collect (subseq s start end)
                     while end)))
    (remove-if (lambda (x) (zerop (length x)))
               (mapcar #'trim parts))))

(defun infer-binding-kind (rhs)
  "Inspect the RHS string of a top-level binding (after trimming and
   stripping the trailing ;). Return one of :scalar :region :unknown."
  (let ((r (trim (or rhs ""))))
    ;; Strip trailing semicolon if present.
    (when (and (plusp (length r))
               (char= (char r (1- (length r))) #\;))
      (setf r (trim (subseq r 0 (1- (length r))))))
    (cond
      ;; AUTO.{...}
      ((cl-ppcre:scan "^\\w+\\s*\\.\\s*\\{" r) :region)
      ;; AUTO.reachable / AUTO.get_invariants / AUTO.is_reachable(...)
      ((cl-ppcre:scan "^\\w+\\s*\\.\\s*(reachable|get_invariants|is_reachable\\s*\\()" r)
       :region)
      ;; Looks like a number (with optional sign, decimal, exponent)
      ((cl-ppcre:scan "^[+-]?[0-9]" r) :scalar)
      (t :unknown))))

(defun scan-symbols (text)
  "Scan TEXT line by line, returning a list of SYMBOL-INFO structs.
   Tracks automaton-block depth so user bindings can be distinguished
   from declarations inside an automaton."
  (let ((results '())
        (in-automaton 0)
        (line-no 0))
    (with-input-from-string (s text)
      (loop for raw = (read-line s nil nil)
            while raw
            do (incf line-no)
               (let ((line (trim raw)))
                 (cond
                   ;; automaton NAME
                   ((cl-ppcre:register-groups-bind (name)
                        ("^automaton\\s+(\\w+)" line)
                      (push (make-symbol-info :name name :kind :automaton :line line-no)
                            results)
                      (incf in-automaton)
                      t))
                   ;; end (only counts when matching an open automaton)
                   ((cl-ppcre:scan "^end\\b" line)
                    (when (plusp in-automaton)
                      (decf in-automaton)))
                   ;; Inside an automaton block: capture loc / contr_var / synclabs
                   ((plusp in-automaton)
                    (cond
                      ((cl-ppcre:register-groups-bind (name)
                           ("^loc\\s+(\\w+)\\s*:" line)
                         (push (make-symbol-info :name name :kind :location :line line-no)
                               results)
                         t))
                      ((cl-ppcre:register-groups-bind (vars)
                           ("^contr_var\\s*:\\s*([^;]+);" line)
                         (dolist (v (split-and-trim vars #\,))
                           (push (make-symbol-info :name v :kind :var :line line-no) results))
                         t))
                      ((cl-ppcre:register-groups-bind (labels)
                           ("^synclabs\\s*:\\s*([^;]+);" line)
                         (dolist (l (split-and-trim labels #\,))
                           (push (make-symbol-info :name l :kind :sync :line line-no) results))
                         t))))
                   ;; Top-level user binding: NAME := RHS;  or  NAME = RHS;
                   ((cl-ppcre:register-groups-bind (name op rhs)
                        ("^(\\w+)\\s*(:=|=)\\s*(.+)$" line)
                      (declare (ignore op))
                      (let ((kind (infer-binding-kind rhs)))
                        ;; If := used, force :scalar regardless of RHS shape.
                        (when (search ":=" line)
                          (setf kind :scalar))
                        (push (make-symbol-info :name name :kind kind :line line-no)
                              results))
                      t))))))
    (nreverse results)))
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: both suites green; `lsp-symbols` deftest passes (9 testing forms).

If "user binding INSIDE automaton…end is NOT collected" fails, the `(plusp in-automaton)` branch is letting the binding pattern through. Verify the cond order: the `(plusp in-automaton)` branch must come BEFORE the user-binding branch.

If the `:=` vs `=` distinction misclassifies a `:=` assignment as `:region`, double-check the `(when (search ":=" line) (setf kind :scalar))` override — it must run AFTER the RHS inference.

- [ ] **Step 5: Commit**

```bash
git add lsp/symbols.lisp lsp-tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project E: symbols.lisp — regex-based symbol scanner

Walks the document line by line, tracking automaton-block depth, and
collects symbols across 5 categories: automaton names, location names,
contr_var variables, synclabs labels, and top-level user bindings.

Kind for user bindings is inferred from RHS shape:
  := NUMBER                  → :scalar
  = AUTO.{...}               → :region
  = AUTO.reachable           → :region
  = AUTO.get_invariants      → :region
  = AUTO.is_reachable(...)   → :region
  = anything else            → :unknown

User bindings INSIDE an automaton…end block are intentionally NOT
collected (locations/contr_vars/synclabs already cover those cases;
arbitrary bindings inside the block aren't standard PHAVer).

9 deftest cases cover all 5 categories + the in-automaton vs
top-level distinction.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: completion.lisp — TDD for `complete-at`

**Files:**
- Modify: `lsp/completion.lisp`
- Modify: `lsp-tests/main.lisp`

- [ ] **Step 1: Write the failing test**

Append to `lsp-tests/main.lisp`:

```lisp
(defun complete (text symbols)
  "Helper: pass TEXT and SYMBOLS to complete-at with offset = (length text).
   Used by tests that want completion at the cursor at end-of-text."
  (phaverlite-lsp/completion:complete-at text (length text) symbols))

(deftest lsp-completion
  (testing "plain prefix 'co' matches keywords + symbol names starting with 'co'"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "cool" :kind :location :line 1)
                          (phaverlite-lsp/symbols:make-symbol-info
                           :name "cond1" :kind :region :line 2)
                          (phaverlite-lsp/symbols:make-symbol-info
                           :name "x" :kind :var :line 3)))
           (results (complete "co" symbols)))
      (ok (member "cool" results :test #'string=))
      (ok (member "cond1" results :test #'string=))
      (ok (member "contr_var" results :test #'string=))
      (ok (not (member "x" results :test #'string=)))))
  (testing "plain prefix at file start with no symbols → only keywords"
    (let ((results (complete "" '())))
      (ok (member "automaton" results :test #'string=))
      (ok (member "end" results :test #'string=))))
  (testing "after 'sys.' where sys is :automaton → automaton-methods only"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "sys" :kind :automaton :line 1)))
           (results (complete "sys." symbols)))
      (ok (member "add_label" results :test #'string=))
      (ok (member "set_partition_constraints" results :test #'string=))
      (ok (member "is_reachable" results :test #'string=))
      (ok (member "reachable" results :test #'string=))
      (ok (member "get_invariants" results :test #'string=))
      ;; NOT keywords or other symbols
      (ok (not (member "automaton" results :test #'string=)))
      (ok (not (member "sys" results :test #'string=)))))
  (testing "after 'bad.' where bad is :region → only 'print'"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "bad" :kind :region :line 1)))
           (results (complete "bad." symbols)))
      (ok (equal '("print") results))))
  (testing "after 'pc.' where pc is :scalar → empty list"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "pc" :kind :scalar :line 1)))
           (results (complete "pc." symbols)))
      (ok (null results))))
  (testing "after 'unknown.' (not in symbols) → empty list"
    (let ((results (complete "unknown." '())))
      (ok (null results))))
  (testing "dot-completion with prefix after dot: 'sys.add' → 'add_label' only"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "sys" :kind :automaton :line 1)))
           (results (complete "sys.add" symbols)))
      (ok (equal '("add_label") results)))))
```

- [ ] **Step 2: Run, verify failure**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: `lsp-completion` fails — `complete-at` undefined.

- [ ] **Step 3: Implement `lsp/completion.lisp`**

Replace the package shell with:

```lisp
;;;; lsp/completion.lisp — keyword + symbol + kind-aware dot completion.

(defpackage #:phaverlite-lsp/completion
  (:use #:cl)
  (:import-from #:phaverlite-lsp/symbols
                #:symbol-info
                #:symbol-info-name
                #:symbol-info-kind)
  (:export #:complete-at
           #:+keywords+
           #:+automaton-methods+
           #:+region-methods+))
(in-package #:phaverlite-lsp/completion)

(defparameter +keywords+
  '("automaton" "loc" "wait" "when" "sync" "do" "goto" "initially"
    "contr_var" "synclabs" "end"))

(defparameter +automaton-methods+
  '("add_label" "set_partition_constraints" "set_refine_constraints"
    "is_reachable" "reachable" "get_invariants"))

(defparameter +region-methods+ '("print"))

(defun ident-char-p (ch)
  (or (alpha-char-p ch) (digit-char-p ch) (char= ch #\_)))

(defun extract-context (text offset)
  "Look at TEXT just before OFFSET. Return one of:
     (:plain prefix)         — plain identifier prefix
     (:dot receiver prefix)  — after RECEIVER. (PREFIX may be empty)"
  (let ((end (min offset (length text))))
    ;; Walk backwards while ident chars
    (let ((p end))
      (loop while (and (> p 0) (ident-char-p (char text (1- p))))
            do (decf p))
      ;; If the char immediately before p is `.`, look back another ident.
      (cond
        ((and (> p 0) (char= (char text (1- p)) #\.))
         (let ((dot-pos (1- p))
               (q (1- p)))
           (loop while (and (> q 0) (ident-char-p (char text (1- q))))
                 do (decf q))
           (if (= q dot-pos)
               ;; "." with no receiver to the left → treat as plain prefix
               (list :plain (subseq text p end))
               (list :dot
                     (subseq text q dot-pos)
                     (subseq text p end)))))
        (t
         (list :plain (subseq text p end)))))))

(defun has-prefix-p (string prefix)
  "Case-sensitive prefix check."
  (let ((sl (length string)) (pl (length prefix)))
    (and (>= sl pl)
         (string= string prefix :end1 pl))))

(defun complete-at (text offset symbols)
  "Return a list of completion strings for the identifier at OFFSET
   in TEXT, given the SYMBOLS scanned from the document."
  (destructuring-bind (kind &rest rest) (extract-context text offset)
    (case kind
      (:dot
       (destructuring-bind (receiver prefix) rest
         (let ((info (find receiver symbols
                           :key #'symbol-info-name :test #'string=)))
           (let ((methods (case (and info (symbol-info-kind info))
                            (:automaton +automaton-methods+)
                            (:region    +region-methods+)
                            (otherwise  '()))))
             (remove-if-not (lambda (m) (has-prefix-p m prefix)) methods)))))
      (:plain
       (let ((prefix (first rest))
             (candidates (append +keywords+
                                 (mapcar #'symbol-info-name symbols))))
         (remove-if-not (lambda (c) (has-prefix-p c prefix)) candidates))))))
```

- [ ] **Step 4: Run, verify pass**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: both suites green; `lsp-completion` deftest passes (7 testing forms).

If "after 'sys.add' → 'add_label' only" fails because the result is a longer list, the `has-prefix-p` filter isn't applied. Verify the dot-branch's final `remove-if-not`.

If "after 'unknown.' → empty list" fails because it returns keywords, the dot-branch is falling through to plain. Verify `find` returns NIL for unknown receivers and the case-fallthrough returns `'()`.

- [ ] **Step 5: Commit**

```bash
git add lsp/completion.lisp lsp-tests/main.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project E: completion.lisp — kind-aware dot completion

complete-at TEXT OFFSET SYMBOLS examines the chars immediately before
OFFSET to detect "RECEIVER.PREFIX" vs "PREFIX" context. Dot context:
look up RECEIVER's kind in SYMBOLS; return automaton-methods for
:automaton, ("print") for :region, () for :scalar/:unknown. Plain
context: keywords + symbol names, prefix-filtered.

7 deftest cases cover plain prefix, empty-symbols-keywords-only,
each receiver kind (automaton/region/scalar/unknown), and dot+prefix.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: server.lisp — JSON-RPC handlers + run-server

**Files:**
- Modify: `lsp/server.lisp`

The server is the integration layer over the three pure modules. Most of the logic is plumbing: wire jsonrpc handlers, manage `*documents*`, convert between LSP wire format (line/character → byte offset) and our internal data. Most testing is manual / via lem in Task 9; here we focus on getting the handlers right.

- [ ] **Step 1: API-grep before code**

```bash
JSONRPC=$(find .qlot -path '*jsonrpc-ref-*' -type d | head -1)
grep -nE 'defun make-server|defun expose|defun server-listen' $JSONRPC/main.lisp $JSONRPC/server.lisp $JSONRPC/mapper.lisp 2>/dev/null
echo "---"
echo "What does expose look like in usage?"
grep -B1 -A3 'jsonrpc:expose\|expose .*server' $JSONRPC/*.lisp 2>/dev/null | head -10
```

Confirm:
- `(jsonrpc:make-server)` returns a server object.
- `(jsonrpc:expose server "method/name" #'handler-fn)` registers a handler.
- `(jsonrpc:server-listen server :mode :stdio)` starts listening.
- `server-listen` returns immediately (the transport spawns its own thread); we need a blocking loop after to keep the process alive.

- [ ] **Step 2: Implement `lsp/server.lisp`**

Replace the package shell with:

```lisp
;;;; lsp/server.lisp — JSON-RPC handlers + run-server.

(defpackage #:phaverlite-lsp/server
  (:use #:cl)
  (:import-from #:phaverlite-lsp/parser
                #:parse-document
                #:diagnostic-start-line
                #:diagnostic-start-col
                #:diagnostic-end-line
                #:diagnostic-end-col
                #:diagnostic-severity
                #:diagnostic-message)
  (:import-from #:phaverlite-lsp/symbols
                #:scan-symbols)
  (:import-from #:phaverlite-lsp/completion
                #:complete-at)
  (:export #:run-server))
(in-package #:phaverlite-lsp/server)

;;; --- document store ----------------------------------------------------

(defvar *documents* (make-hash-table :test 'equal)
  "uri → DOCUMENT struct.")

(defstruct document
  uri text version
  symbols)              ; cached output of scan-symbols

;;; --- helpers -----------------------------------------------------------

(defun get-field (params key)
  "Look up KEY (string) in a hash-table or alist or plist PARAMS.
   jsonrpc / yason returns hash-tables by default; defensive fallbacks."
  (cond
    ((hash-table-p params) (gethash key params))
    ((and (consp params) (consp (car params)))
     (cdr (assoc key params :test #'equal)))
    (t nil)))

(defun line-character-to-offset (text line character)
  "LSP positions are 0-based (line, character). Convert to a byte offset
   in TEXT. Clamp to [0, length)."
  (let ((offset 0)
        (current-line 0)
        (len (length text)))
    (loop while (and (< offset len) (< current-line line))
          do (when (char= (char text offset) #\newline)
               (incf current-line))
             (incf offset))
    (let ((line-end (or (position #\newline text :start offset) len)))
      (min (+ offset character) line-end len))))

(defun severity->lsp (sev)
  "LSP severity: 1=error, 2=warning, 3=info, 4=hint."
  (case sev (:error 1) (:warning 2) (otherwise 3)))

(defun diagnostic->lsp (d)
  "Convert our DIAGNOSTIC struct → LSP Diagnostic alist (yason-friendly)."
  `(("range" . (("start" . (("line" . ,(1- (diagnostic-start-line d)))
                            ("character" . ,(1- (diagnostic-start-col d)))))
                ("end"   . (("line" . ,(1- (diagnostic-end-line d)))
                            ("character" . ,(1- (diagnostic-end-col d)))))))
    ("severity" . ,(severity->lsp (diagnostic-severity d)))
    ("message"  . ,(diagnostic-message d))
    ("source"   . "phaverlite-lsp")))

(defun publish-diagnostics (server uri diags)
  (jsonrpc:notify server "textDocument/publishDiagnostics"
                  `(("uri" . ,uri)
                    ("diagnostics" . ,(mapcar #'diagnostic->lsp diags)))))

(defun reparse-and-publish (server uri text)
  (let ((diags (handler-case (parse-document text)
                 (error (e)
                   (format *error-output* "parser error: ~a~%" e)
                   '()))))
    (publish-diagnostics server uri diags)))

;;; --- handlers ----------------------------------------------------------

(defun handle-initialize (server params)
  (declare (ignore server params))
  `(("capabilities"
     . (("textDocumentSync" . 1)            ; full sync
        ("completionProvider"
         . (("triggerCharacters" . ("."))))))))

(defun handle-initialized (server params)
  (declare (ignore server params))
  :null)

(defun handle-shutdown (server params)
  (declare (ignore server params))
  :null)

(defun handle-exit (server params)
  (declare (ignore server params))
  (uiop:quit 0))

(defun handle-did-open (server params)
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (text (get-field td "text"))
         (version (get-field td "version")))
    (setf (gethash uri *documents*)
          (make-document :uri uri :text text :version version
                         :symbols (handler-case (scan-symbols text)
                                    (error (e)
                                      (format *error-output* "scan-symbols error: ~a~%" e)
                                      '()))))
    (reparse-and-publish server uri text)
    :null))

(defun handle-did-change (server params)
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (changes (get-field params "contentChanges"))
         ;; Full sync — last change is the new full text.
         (new-text (get-field (car (last changes)) "text"))
         (doc (gethash uri *documents*)))
    (when doc
      (setf (document-text doc) new-text
            (document-symbols doc) (handler-case (scan-symbols new-text)
                                     (error (e)
                                       (format *error-output* "scan error: ~a~%" e)
                                       '())))
      (reparse-and-publish server uri new-text))
    :null))

(defun handle-did-save (server params)
  (handle-did-change server params))

(defun handle-did-close (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri")))
    (remhash uri *documents*)
    :null))

(defun handle-completion (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (pos (get-field params "position"))
         (line (get-field pos "line"))
         (character (get-field pos "character"))
         (doc (gethash uri *documents*))
         (items '()))
    (when doc
      (let* ((offset (line-character-to-offset (document-text doc) line character))
             (completions (handler-case
                              (complete-at (document-text doc) offset
                                           (document-symbols doc))
                            (error (e)
                              (format *error-output* "complete-at error: ~a~%" e)
                              '()))))
        (setf items
              (mapcar (lambda (label)
                        `(("label" . ,label) ("kind" . 14)))   ; 14 = Keyword
                      completions))))
    `(("isIncomplete" . :false)
      ("items" . ,items))))

;;; --- entry point -------------------------------------------------------

(defun run-server ()
  "Start the LSP server on stdio. Blocks until exit."
  (let ((server (jsonrpc:make-server)))
    (jsonrpc:expose server "initialize"          (lambda (p) (handle-initialize server p)))
    (jsonrpc:expose server "initialized"         (lambda (p) (handle-initialized server p)))
    (jsonrpc:expose server "shutdown"            (lambda (p) (handle-shutdown server p)))
    (jsonrpc:expose server "exit"                (lambda (p) (handle-exit server p)))
    (jsonrpc:expose server "textDocument/didOpen"  (lambda (p) (handle-did-open server p)))
    (jsonrpc:expose server "textDocument/didChange" (lambda (p) (handle-did-change server p)))
    (jsonrpc:expose server "textDocument/didSave"  (lambda (p) (handle-did-save server p)))
    (jsonrpc:expose server "textDocument/didClose" (lambda (p) (handle-did-close server p)))
    (jsonrpc:expose server "textDocument/completion" (lambda (p) (handle-completion server p)))
    (jsonrpc:server-listen server :mode :stdio)
    ;; server-listen returns; block until exit handler calls (uiop:quit).
    (loop (sleep 1))))
```

- [ ] **Step 3: Verify the system still loads (no regression on prior tasks)**

```bash
bin/test-mode 2>&1 | tail -10
```

Expected: both suites still green. (No new tests in this task — handlers are exercised manually in Task 9 via lem.)

If the load fails because `jsonrpc:notify` doesn't exist, the lib's name might be `jsonrpc/main:notify` or the function might be `jsonrpc:send-notification`. Re-grep `$JSONRPC/main.lisp`'s exports for the right name.

- [ ] **Step 4: Quick sanity check — server boots without crashing**

The server can be started directly (it'll hang waiting for stdin):

```bash
echo "" | timeout 2 qlot exec sbcl \
  --noinform --no-userinit --no-sysinit \
  --eval '(pushnew (truename ".") asdf:*central-registry* :test #'\''equal)' \
  --eval '(ql:quickload :phaverlite-lsp :silent t)' \
  --eval '(phaverlite-lsp/main:run)' 2>&1 | head -5
```

(macOS doesn't have `timeout` — if so, just run without `timeout` and Ctrl-C after a second.)

Expected: NO crash, no errors. Process is blocked waiting for JSON-RPC input. Killing it is fine.

If you see "Unknown mode :stdio" — `jsonrpc/transport/stdio` system isn't loaded. Make sure `phaverlite-lsp.asd` lists it as a dep (Task 1's `:depends-on` should have it).

If you see "Component jsonrpc/transport/stdio not found" — qlot install hasn't pulled the sub-system. Add `git jsonrpc/transport/stdio` to qlfile? Actually no — jsonrpc's components include the transport sub-systems automatically. If this fails, see what `(asdf:find-system :jsonrpc/transport/stdio)` returns.

- [ ] **Step 5: Commit**

```bash
git add lsp/server.lisp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project E: server.lisp — JSON-RPC handlers + run-server

Wires the three pure modules (parser, symbols, completion) behind
JSON-RPC handlers for the standard LSP lifecycle:
  initialize / initialized / shutdown / exit
  textDocument/didOpen | didChange | didSave | didClose
  textDocument/completion

didOpen and didChange re-parse + re-scan + publish diagnostics
(textDocument/publishDiagnostics notification). completion delegates
to complete-at after converting LSP (line, character) to byte offset.

Each handler is wrapped in handler-case at the boundary; logged
errors go to stderr (becomes lem's *Messages*); empty/safe results
returned. Server NEVER dies on a single bad request — only via
shutdown/exit handshake or (uiop:quit 0).

run-server uses jsonrpc:server-listen with :mode :stdio (lazy-loads
jsonrpc/transport/stdio), then blocks on (loop (sleep 1)) until the
exit handler quits the process.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: bin/phaverlite-lsp launcher

**Files:**
- Create: `bin/phaverlite-lsp` (executable)

- [ ] **Step 1: Create the launcher**

```bash
cat > bin/phaverlite-lsp <<'EOF'
#!/usr/bin/env zsh
# bin/phaverlite-lsp — launch the phaverlite LSP server in stdio mode.
# Spawned by lem-lsp-mode when a .pha buffer opens.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v qlot >/dev/null 2>&1; then
  print -u2 "phaverlite-lsp: 'qlot' not found on PATH."
  exit 1
fi
if [[ ! -d "$REPO/.qlot" ]]; then
  print -u2 "phaverlite-lsp: $REPO/.qlot/ missing. Run 'qlot install' first."
  exit 1
fi

cd "$REPO"
exec qlot exec sbcl \
  --noinform --no-userinit --no-sysinit \
  --eval '(pushnew (truename ".") asdf:*central-registry* :test #'\''equal)' \
  --eval '(ql:quickload :phaverlite-lsp :silent t)' \
  --eval '(phaverlite-lsp/main:run)'
EOF
chmod +x bin/phaverlite-lsp
```

- [ ] **Step 2: Verify the launcher boots the server**

```bash
echo "" | bin/phaverlite-lsp 2>&1 | head -5 &
sleep 2
jobs -p | xargs -I {} kill {} 2>/dev/null
```

Expected: no error output in those first 5 lines (the server is just blocked waiting for input). If you see SBCL startup errors or "Component not found", fix before proceeding.

- [ ] **Step 3: Commit**

```bash
git add bin/phaverlite-lsp
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project E: bin/phaverlite-lsp launcher

zsh launcher matching the bin/phaverlite-ide pattern. Spawned by
lem-lsp-mode when a .pha buffer opens. exec's qlot exec sbcl with
--script-style invocation that pushes the repo onto asdf central
registry, quickloads phaverlite-lsp, and calls
(phaverlite-lsp/main:run).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Client glue — `phaverlite-mode-lsp.asd` + `src-lsp/spec.lisp` + init.lisp + build-image

**Files:**
- Create: `phaverlite-mode-lsp.asd`
- Create: `src-lsp/spec.lisp`
- Modify: `config/init.lisp`
- Modify: `bin/build-image`

- [ ] **Step 1: Create `phaverlite-mode-lsp.asd`**

```lisp
;;;; phaverlite-mode-lsp.asd — client-side glue inside lem.
;;;; Registers the phaverlite LSP server with lem-lsp-mode for
;;;; phaverlite-mode buffers.

(defsystem "phaverlite-mode-lsp"
  :description "lem-lsp-mode glue for phaverlite-mode."
  :depends-on ("phaverlite-mode" "lem-lsp-mode")
  :pathname "src-lsp"
  :serial t
  :components ((:file "spec")))
```

- [ ] **Step 2: Create `src-lsp/spec.lisp`**

```lisp
;;;; src-lsp/spec.lisp — register the phaverlite LSP server with
;;;; lem-lsp-mode. One define-language-spec form, period.

(defpackage #:phaverlite-mode-lsp
  (:use #:cl))
(in-package #:phaverlite-mode-lsp)

(lem-lsp-mode/lsp-mode:define-language-spec
    (phaverlite-spec phaverlite-mode:phaverlite-mode)
  :language-id "phaverlite"
  :command (list (namestring (merge-pathnames "bin/phaverlite-lsp"
                                              (uiop:getcwd))))
  :connection-mode :stdio)
```

- [ ] **Step 3: Verify both systems load together inside lem-aware sbcl**

```bash
PHAVERLITE_IDE_LIB="$PWD/var/lib" qlot exec sbcl \
  --noinform --no-userinit --no-sysinit \
  --eval '(ql:quickload :cffi :silent t)' \
  --eval "(let ((d (uiop:getenv \"PHAVERLITE_IDE_LIB\"))) (when d (pushnew (uiop:ensure-directory-pathname d) cffi:*foreign-library-directories* :test #'equal)))" \
  --eval '(pushnew (truename ".") asdf:*central-registry* :test #'\''equal)' \
  --eval '(ql:quickload :lem-ncurses :silent t)' \
  --eval '(ql:quickload :phaverlite-mode :silent t)' \
  --eval '(ql:quickload :phaverlite-mode-lsp :silent t)' \
  --eval '(format t "loaded: ~a~%" (find-package :phaverlite-mode-lsp))' \
  --eval '(uiop:quit 0)'
```

Expected: `loaded: #<PACKAGE "PHAVERLITE-MODE-LSP">` and exit 0.

If `lem-lsp-mode` isn't found, it's part of lem and lem-ncurses loads it transitively; if not, add an explicit `(ql:quickload :lem-lsp-mode)` before phaverlite-mode-lsp.

- [ ] **Step 4: Wire `config/init.lisp` to quickload phaverlite-mode-lsp**

Open `config/init.lisp`. Find the existing line:
```lisp
(ql:quickload :phaverlite-mode :silent t)
```

Insert AFTER it:
```lisp
(ql:quickload :phaverlite-mode-lsp :silent t)
```

- [ ] **Step 5: Wire `bin/build-image` likewise**

Open `bin/build-image`. Find the existing `--eval '(ql:quickload :phaverlite-mode :silent t)'` line.

Insert AFTER it (a new `--eval` that quickloads phaverlite-mode-lsp):
```sh
  --eval '(ql:quickload :phaverlite-mode-lsp :silent t)' \
```

(Mind the trailing backslash for shell line continuation.)

- [ ] **Step 6: Run `bin/test-mode` for regression**

```bash
bin/test-mode 2>&1 | tail -5
```

Expected: both suites still green. (No new tests for the client glue — verified manually in Task 9.)

- [ ] **Step 7: Commit**

```bash
git add phaverlite-mode-lsp.asd src-lsp/spec.lisp config/init.lisp bin/build-image
bin/privacy-preflight staged || exit 1
git commit -m "$(cat <<'EOF'
sub-project E: client glue + init.lisp + build-image wiring

phaverlite-mode-lsp ASDF system at repo root. Single source file
(src-lsp/spec.lisp) with one define-language-spec form binding our
LSP server to phaverlite-mode buffers (language-id "phaverlite",
command bin/phaverlite-lsp, stdio transport).

config/init.lisp + bin/build-image both quickload the new system
so the image bakes the registration; opening any .pha file in lem
will spawn bin/phaverlite-lsp via lem-lsp-mode.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Image rebuild + smoke test in lem + isolation regression + push

**Files touched (verification only):**
- Regenerated: `var/lem.core`

- [ ] **Step 1: Rebuild the lem core**

```bash
bin/build-image 2>&1 | tail -3
```

Expected: `build-image: done. Output: ...var/lem.core` ~30-60s, ~119M.

If you see `Component "phaverlite-mode-lsp" not found`, the central-registry push isn't picking up the new asd. Verify `ls phaverlite-mode-lsp.asd` and that bin/build-image runs `cd "$REPO"` before sbcl.

If you see `Symbol LEM-LSP-MODE/LSP-MODE:DEFINE-LANGUAGE-SPEC not found`, lem-lsp-mode wasn't loaded transitively. Add `(ql:quickload :lem-lsp-mode :silent t)` before phaverlite-mode-lsp in build-image.

- [ ] **Step 2: Final test-mode regression**

```bash
bin/test-mode 2>&1 | tail -5
```

Expected: both suites green, exit 0.

- [ ] **Step 3: Smoke test in lem — diagnostics**

```bash
bin/phaverlite-ide
```

In lem:
1. `C-x C-f examples/cycler.pha` → opens in PHAVer mode.
2. Wait ~1s for LSP server to spawn. Check `*Messages*` for "phaverlite-lsp" or similar connection log line.
3. Delete the trailing `end` of the `automaton sys` block. Within ~1s an error squiggle should appear on the `automaton sys` line, message about missing `end`.
4. Restore the `end`. Squiggle clears.
5. Add an unmatched `{` somewhere inside a wait expression. Squiggle on that brace.
6. Restore. Squiggle clears.

If no squiggles appear at all, the LSP server didn't start. Debug:
- Check `bin/phaverlite-lsp` runs standalone (Task 7 step 2).
- Check `*Messages*` in lem for an error from lem-lsp-mode (e.g., "command not found" or stderr from the server).
- Check the bin/phaverlite-lsp permissions (executable).

- [ ] **Step 4: Smoke test in lem — autocomplete**

In lem with `examples/cycler.pha` open:
1. Place point at end of file, after `end` of the automaton.
2. Type `aut` then `M-x lsp-completion` (or rely on auto-complete if lem-lsp-mode triggers it). Should suggest `automaton`.
3. Inside the file, find a use of `sys.is_reachable(bad);`. Move point right after `sys.` (delete `is_reachable(bad);` first). Trigger completion. Should show `add_label`, `set_partition_constraints`, `set_refine_constraints`, `is_reachable`, `reachable`, `get_invariants` — and ONLY those.
4. After `bad.` (delete the trailing characters of an existing region usage). Trigger completion. Should show `print` only.
5. After `pc.` (`pc` was declared via `pc := __PC__;` — make a local copy). Trigger completion. Should be empty.

- [ ] **Step 5: Wrong-buffer / non-pha buffer**

`C-x b *tmp*`. Type `automaton`. The completion should NOT fire (no LSP for *tmp*).

- [ ] **Step 6: Exit lem and run isolation regression**

`C-x C-c`. Then:

```bash
bin/verify-isolation
```

Expected: `[verify-isolation] PASS: no changes under watched paths.`

(`verify-isolation` re-launches lem; just `C-x C-c` again when it does.)

- [ ] **Step 7: Privacy preflight + push (only when user has approved)**

```bash
bin/privacy-preflight unpushed
```

If clean and the user has approved push:

```bash
git push origin main
```

---

## Definition-of-done checklist (verify against spec after Task 9)

- [ ] (DoD 1) `phaverlite-lsp` system loads without lem deps.
- [ ] (DoD 2) `phaverlite-mode-lsp` system loads inside lem-aware sbcl.
- [ ] (DoD 3) `bin/phaverlite-lsp` is executable and runs the server in stdio mode.
- [ ] (DoD 4) `config/init.lisp` loads `phaverlite-mode-lsp`.
- [ ] (DoD 5) Opening a `.pha` file spawns the server; LSP handshake succeeds.
- [ ] (DoD 6) Live diagnostics: missing `end` / unmatched brace produce squiggles within ~1s; restoration clears them.
- [ ] (DoD 7) Autocomplete: keyword + symbol prefix completion works; kind-aware dot-completion works for :automaton (full method list) / :region (`print`) / :scalar (empty).
- [ ] (DoD 8) `bin/test-mode` runs both suites and exits 0.
- [ ] (DoD 9) `bin/verify-isolation` PASS.
