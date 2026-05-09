# Sub-project E — `phaverlite-lsp` (minimal LSP for code intelligence)

**Date:** 2026-05-09
**Status:** Approved design, not yet implemented
**Scope:** Fifth and final sub-project. Builds on A, B, C, D. See
`CLAUDE.md` for the A→B→(C,D,E) decomposition.

## Goal

A minimal Language Server Protocol implementation for `.pha` files,
providing two code-intelligence features:

1. **Diagnostics** — hand-rolled structural parser checks for unmatched
   braces (`{} () []`), `automaton` without matching `end`, orphan `end`,
   missing `;` at obvious positions. Reported as squiggles in lem with
   precise line/column ranges. Live on every `textDocument/didChange`.
2. **Autocomplete** — `textDocument/completion` returns:
   - Static PHAVer keywords (`automaton`, `loc`, `wait`, `when`, `sync`,
     `do`, `goto`, `initially`, `contr_var`, `synclabs`, `end`).
   - User-declared symbols extracted by regex scan: automaton names,
     location names, contr_var variables, synclabs labels, top-level
     user bindings (`pc`, `bad`, `cond1`, `reg`, `inv`, etc.).
   - **Kind-aware dot-completion:** when cursor sits after `IDENT.`,
     return only the methods valid for IDENT's kind:
     - `:automaton` kind → `add_label`, `set_partition_constraints`,
       `set_refine_constraints`, `is_reachable`, `reachable`,
       `get_invariants`
     - `:region` kind → `print`
     - `:scalar` kind → no methods
     - unknown / kind-not-tracked → no methods

The server speaks JSON-RPC over stdio (per CLAUDE.md spec, no external
LSP framework). Lem's built-in `lem-lsp-mode` is the client.

## Definition of done

1. `phaverlite-lsp` ASDF system loads cleanly (no lem deps in the
   server — `:depends-on ("jsonrpc" "cl-ppcre")`).
2. `phaverlite-mode-lsp` ASDF system loads cleanly inside lem
   (depends on `phaverlite-mode` + `lem-lsp-mode`).
3. `bin/phaverlite-lsp` is an executable zsh launcher that starts
   the server in stdio mode (`exec qlot exec sbcl --script` style).
4. `config/init.lisp` loads `phaverlite-mode-lsp` so the
   `define-language-spec` registers our server with lem-lsp-mode.
5. Opening a `.pha` file in lem spawns `bin/phaverlite-lsp` as a
   subprocess; lem and the server complete the LSP initialize
   handshake successfully.
6. **Diagnostics:**
   - Editing a `.pha` file triggers `textDocument/didChange`; the
     server publishes diagnostics; lem squiggles them.
   - Removing the trailing `end` of an `automaton` produces an error
     squiggle on the `automaton` line within ~1 second of the edit.
   - Restoring `end` clears the squiggle.
   - Diagnostic ranges have correct line+column.
7. **Autocomplete:**
   - Typing a partial keyword (e.g. `aut`) and triggering completion
     returns `automaton`.
   - Typing a partial user-declared symbol (e.g. `co` after declaring
     `cond1`, `cond2`, `cool`) returns those, prefix-filtered.
   - Typing `IDENT.` where IDENT was declared via `automaton` returns
     the automaton method list and NOT keywords or user names.
   - Typing `IDENT.` where IDENT was declared via `IDENT = AUTO.{...}`
     or `IDENT = AUTO.reachable` returns `("print")` only.
   - Typing `IDENT.` where IDENT was declared via `IDENT := NUMBER`
     returns `()`.
8. `bin/test-mode` runs BOTH `phaverlite-mode-tests` and
   `phaverlite-lsp-tests` and exits 0.
9. `bin/verify-isolation` PASS (server inherits the env-isolated
   PATH/$HOME from lem-lsp-mode's spawn).

**Out of scope for E:**
- Hover (`textDocument/hover`) — keyword docs.
- Go-to-definition (`textDocument/definition`).
- Find-references (`textDocument/references`).
- Document symbols (`textDocument/documentSymbol`) — the outline view.
- Rename, code actions, formatting, signature help.
- Semantic tokens (server-driven syntax highlighting).
- Multi-file projects / workspace symbols.
- Parser warnings (stylistic) — only hard errors in prototype.
- Scope-aware completion — locations / contr_vars / synclabs are
  collected flat across all automata in the file. Editing inside
  `automaton heater` may show locations from `automaton bball`.
  Acceptable noise for prototype; tighten by tracking automaton
  boundaries later.
- Server-side image dumping (`var/lsp.core` for fast startup).
  Cold-start the server via `--script` each spawn (~2-3s). Add
  image dumping later if startup proves annoying.
- Phaverlite-as-validator diagnostics (running `phaverlite` on save
  and parsing its parse-error output). Considered and rejected:
  the structural parser gives faster feedback and precise ranges.
  Could be added as a complementary mode later.
- End-to-end JSON-RPC roundtrip tests (spawning the server,
  framing requests, parsing responses). The server's pure modules
  are unit-tested; end-to-end is verified by the manual smoke checks.

## Architecture

**Two new ASDF systems** (the client glue and the LSP server have
opposite dependency requirements and would couple awkwardly into one):

```
phaverlite-lsp.asd                  at repo root
                                     (defsystem "phaverlite-lsp"
                                       :depends-on ("jsonrpc" "cl-ppcre")
                                       :pathname "lsp"
                                       :serial t
                                       :components ((:file "parser")
                                                    (:file "symbols")
                                                    (:file "completion")
                                                    (:file "server")
                                                    (:file "main")))
lsp/
  parser.lisp                       package phaverlite-lsp/parser
                                     — parse-document text → list of diagnostic
  symbols.lisp                      package phaverlite-lsp/symbols
                                     — scan-symbols text → list of symbol-info
                                       with kind tracking
  completion.lisp                   package phaverlite-lsp/completion
                                     — complete-at text offset symbols → list
  server.lisp                       package phaverlite-lsp/server
                                     — JSON-RPC lifecycle, didOpen/didChange/
                                       didSave/completion handlers, run-server
  main.lisp                         package phaverlite-lsp/main
                                     — script entry: (run-server)

phaverlite-mode-lsp.asd             at repo root
                                     (defsystem "phaverlite-mode-lsp"
                                       :depends-on ("phaverlite-mode"
                                                    "lem-lsp-mode")
                                       :pathname "src-lsp"
                                       :serial t
                                       :components ((:file "spec")))
src-lsp/
  spec.lisp                         package phaverlite-mode-lsp
                                     — single define-language-spec form
                                       binding our server to phaverlite-mode

phaverlite-lsp-tests.asd            at repo root
                                     (defsystem "phaverlite-lsp-tests"
                                       :depends-on ("phaverlite-lsp" "rove")
                                       :pathname "lsp-tests"
                                       :components ((:file "main"))
                                       :perform (test-op (op c)
                                                  (symbol-call :rove '#:run c)))
lsp-tests/
  main.lisp                         package phaverlite-lsp/tests
                                     (deftest lsp-parser …)
                                     (deftest lsp-symbols …)
                                     (deftest lsp-completion …)

bin/phaverlite-lsp                  executable zsh launcher (see below)
config/init.lisp                    +1 line:
                                       (ql:quickload :phaverlite-mode-lsp
                                                     :silent t)
bin/test-mode                       +1 invocation: also run
                                       (asdf:test-system :phaverlite-lsp-tests)
                                     in a SECOND sbcl (no lem deps).
```

**Why split into two systems:**
- The server runs as a separate process spawned by `lem-lsp-mode`. It
  doesn't need lem loaded — pulling in `lem/core` would balloon a
  small server with megabytes of unrelated code and slow startup.
- The client glue has the OPPOSITE deps (`lem-lsp-mode`), so it can't
  share the server's asd.
- Tests for the server are pure-functional and run in their own sbcl
  (no lem load → fast). Tests for the client glue are skipped — the
  one form is verified by manual smoke check.

**`bin/phaverlite-lsp` (executable zsh launcher):**

```sh
#!/usr/bin/env zsh
# bin/phaverlite-lsp — launch the phaverlite LSP server in stdio mode.
# Spawned by lem-lsp-mode when a .pha buffer opens.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

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
```

**`qlfile` change:** `cl-ppcre` is already a transitive dep (lem uses
it widely); adding `phaverlite-lsp` shouldn't require new entries.
`jsonrpc` was already added in sub-project A's qlfile. Verify on first
`qlot install` after the asd is committed; if cl-ppcre isn't
transitively present, add `ql cl-ppcre` to qlfile.

**Image rebuild required after E:** `config/init.lisp` gains a
quickload, so `bin/build-image` rebakes `var/lem.core`. The server is
launched on demand by lem-lsp-mode; the launcher uses `--script` (no
separate image needed).

## Components

### `lsp/parser.lisp` — `phaverlite-lsp/parser`

```lisp
(defstruct diagnostic
  start-line start-col end-line end-col
  severity              ; :error | :warning
  message)

(defun parse-document (text) → list of DIAGNOSTIC
  ;; Token-stream scan over TEXT. Reports:
  ;;   - unmatched braces { } ( ) [ ]
  ;;   - automaton without matching end (range = the automaton line)
  ;;   - end without preceding automaton (range = the end line)
  ;;   - mismatched bracket pairs ({)} → diagnostic at the closer
  ;; Empty list = clean file. severity is :error for all checks
  ;; in this prototype.
  )
```

Implementation strategy: line-by-line scan tracking a stack of open
brackets (each entry = (kind line col)). On close-bracket, pop and
verify matching kind. At EOF, any remaining stack entries are
unmatched-open diagnostics. Block keywords (`automaton`, `end`)
maintain a parallel stack with the same logic.

### `lsp/symbols.lisp` — `phaverlite-lsp/symbols`

```lisp
(defstruct symbol-info
  name                  ; string
  kind                  ; :keyword | :automaton | :location | :var
                        ; | :sync | :region | :scalar | :unknown
  line)                 ; 1-based source line

(defun scan-symbols (text) → list of SYMBOL-INFO
  ;; Pure regex scan, line-by-line, tracking automaton-block depth so
  ;; "top-level" user bindings can be distinguished from declarations
  ;; inside an automaton.
  ;;
  ;; Patterns (anchored to start-of-trimmed-line):
  ;;   ^automaton\s+(\w+)            → :automaton
  ;;   ^loc\s+(\w+)\s*:              → :location  (only inside an automaton)
  ;;   ^contr_var\s*:\s*([^;]+);     → split on , trim → :var (each)
  ;;   ^synclabs\s*:\s*([^;]+);      → split on , trim → :sync (each)
  ;;   ^end\b                        → exit automaton block
  ;;   ^(\w+)\s*[:]?=\s*(.*);        → top-level user binding (when
  ;;                                    NOT inside an automaton)
  ;;
  ;; Kind for user bindings is inferred from RHS shape:
  ;;   := NUMBER                    → :scalar
  ;;   = AUTO.{...}                 → :region
  ;;   = AUTO.reachable             → :region
  ;;   = AUTO.get_invariants        → :region
  ;;   = AUTO.is_reachable(...)     → :region (PHAVer treats these as
  ;;                                   region values for `print` purposes)
  ;;   = anything else              → :unknown
  )
```

### `lsp/completion.lisp` — `phaverlite-lsp/completion`

```lisp
(defparameter +keywords+
  '("automaton" "loc" "wait" "when" "sync" "do" "goto" "initially"
    "contr_var" "synclabs" "end"))

(defparameter +automaton-methods+
  '("add_label" "set_partition_constraints" "set_refine_constraints"
    "is_reachable" "reachable" "get_invariants"))

(defparameter +region-methods+ '("print"))

(defun complete-at (text offset symbols) → list of completion strings
  ;; 1. Inspect chars immediately before OFFSET.
  ;; 2. If pattern is "RECEIVER.PREFIX" (PREFIX may be empty):
  ;;      look up RECEIVER in SYMBOLS by name
  ;;      case (symbol-info-kind …):
  ;;        :automaton → +automaton-methods+
  ;;        :region    → +region-methods+
  ;;        otherwise  → '()
  ;;      filter by PREFIX, return.
  ;; 3. Otherwise (plain prefix):
  ;;      union of +keywords+ and (mapcar #'symbol-info-name SYMBOLS)
  ;;      filter by prefix, return.
  )
```

### `lsp/server.lisp` — `phaverlite-lsp/server`

```lisp
(defvar *documents* (make-hash-table :test 'equal)
  "uri → DOCUMENT struct.")

(defstruct document
  uri text version
  symbols)              ; cached output of (scan-symbols text)

(defun handle-initialize (params) → result
  ;; Returns server-capabilities: textDocumentSync = full,
  ;; completionProvider with triggerCharacters '("." ).
  )

(defun handle-did-open    (params))   ; store doc, parse, publish
(defun handle-did-change  (params))   ; replace text, re-parse, publish
(defun handle-did-save    (params))   ; same as did-change
(defun handle-did-close   (params))   ; remhash uri
(defun handle-completion  (params))   ; lookup doc, delegate to complete-at

(defun run-server ()
  ;; jsonrpc:make-server, register methods, jsonrpc:server-listen :stdio.
  ;; Wraps every handler in handler-case; logs errors to stderr;
  ;; never exits except via shutdown/exit handshake.
  )
```

### `lsp/main.lisp` — `phaverlite-lsp/main`

```lisp
(defpackage #:phaverlite-lsp/main
  (:use #:cl)
  (:export #:run))
(in-package #:phaverlite-lsp/main)

(defun run ()
  (phaverlite-lsp/server:run-server))
```

(Trivial wrapper kept separate so the server module remains library-style.)

### `src-lsp/spec.lisp` — `phaverlite-mode-lsp`

```lisp
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

## Data flow

**Server lifecycle (one process per `.pha` buffer):**

```
user opens cycler.pha in lem
  → phaverlite-mode activates (sub-project B)
  → lem-lsp-mode notices a registered language-spec for phaverlite-mode
  → lem-lsp-mode spawns: bin/phaverlite-lsp  (subprocess, stdin/stdout)
  → lem ↔ server JSON-RPC handshake:
      → initialize { rootUri, capabilities, … }
      ← server: { capabilities: { textDocumentSync: full,
                                  completionProvider: {triggerCharacters: ["."]} } }
      → initialized
  → lem sends textDocument/didOpen { uri, languageId: "phaverlite", text }
      → server stores doc, runs (parse-document text) and (scan-symbols text)
      ← server publishes textDocument/publishDiagnostics { uri, diagnostics }
  → lem squiggles the diagnostics
```

**Edit cycle:**

```
user types in lem
  → lem-lsp-mode buffers + sends textDocument/didChange (full sync)
  → server: replace stored text, re-parse, re-scan, publish diagnostics
  → lem updates squiggles
```

**Completion request:**

```
user types `sys1.` then completion auto-fires (trigger char ".") OR M-x
  → lem sends textDocument/completion { uri, position: { line, character } }
  → server:
      look up document by uri
      compute byte offset from (line, character)
      delegate to (complete-at text offset symbols)
        complete-at:
          inspect chars before offset
          if "IDENT.":
            look up IDENT in symbols → kind
            return per-kind method list, prefix-filtered
          else:
            return keywords + symbol names, prefix-filtered
  ← server: { items: [{label: "add_label", kind: 2}, …] }
  → lem-lsp-mode pops the completion menu
```

**Save / shutdown:**

```
user saves the file
  → textDocument/didSave (didChange already fired during typing)
  → server: re-parse, publish diagnostics
user closes the buffer
  → textDocument/didClose
  → server: (remhash uri *documents*); process stays alive (other .pha
    buffers may share this server depending on lem-lsp-mode's policy)
user closes lem
  → shutdown then exit
  → server: (uiop:quit 0)
```

## Error handling

| Where | Failure | Policy |
|---|---|---|
| `bin/phaverlite-lsp` not found / not executable | Lem can't spawn server | `lem-lsp-mode` shows error in `*Messages*`; LSP features unavailable for this buffer; phaverlite-mode itself unaffected (squiggles + completion gone, but mode still works) |
| `qlot` / `.qlot/` missing | Server boot fails immediately | `bin/phaverlite-lsp` errors fast on missing precondition (mirrors `bin/phaverlite-ide`'s checks) |
| Server SBCL load errors | Server exits non-zero before initialize | `lem-lsp-mode` shows the stderr in `*Messages*` |
| Malformed JSON-RPC from client | `jsonrpc` library raises | Library converts to JSON-RPC error response (-32700 ParseError); server stays up |
| Unknown method in request | Dispatcher raises | JSON-RPC -32601 MethodNotFound; server stays up |
| `parse-document` raises mid-edit | Bug in our parser on weird input | Wrap dispatcher in `handler-case`: log to stderr (becomes `*Messages*`), publish empty diagnostics so squiggles clear, server stays up |
| `scan-symbols` raises | Same as above | Same: log + treat as empty symbol list for completion |
| `complete-at` raises | Same | Same: log + return empty completion list |
| Document URI not in `*documents*` | Out-of-order requests | Return empty diagnostics / empty completion; no error response |
| Cursor offset out of bounds | Stale position from race | Clamp to `[0, length)`; gracefully return empty list at file end |
| Server-side OOM / unbounded growth | Pathological input | None for prototype. Lem-lsp-mode notices server died and reports it; user restarts |
| Concurrent requests during fast typing | jsonrpc lib serializes by default | Single-threaded server; requests processed in order. No data races on `*documents*` |
| Lem-side: server doesn't respond within timeout | `lem-lsp-mode` retries / gives up | Lem's responsibility. Server should be fast (parse + scan are O(file_size)) |

**Crash isolation rule:** every JSON-RPC handler is wrapped in
`handler-case`. The server NEVER dies on a single bad request — it
logs to stderr and returns an empty / safe result. The only paths
that exit the process: (1) explicit shutdown + exit, (2) `(uiop:quit 0)`
from the entry point.

**Diagnostic semantics:**
- `severity = :error` for things `phaverlite` would reject (unmatched
  braces, missing `end`).
- `severity = :warning` for stylistic issues — none in prototype.
- Empty diagnostics list = file is clean. Lem clears prior squiggles
  on receiving `publishDiagnostics` with empty array.

## Testing

Two test invocations in `bin/test-mode`, sequential, separate sbcl per
suite:

```sh
# (existing — phaverlite-mode-tests, requires lem)
qlot exec sbcl … --eval '(asdf:test-system :phaverlite-mode-tests)'

# (new — phaverlite-lsp-tests, no lem deps, fast load)
qlot exec sbcl … --eval '(asdf:test-system :phaverlite-lsp-tests)'
```

Two separate sbcl invocations because the server-tests sbcl doesn't
need lem (and shouldn't pay for loading it). Each prints its own
rove summary. `bin/test-mode` exits 0 only if BOTH succeed.

### New deftests in `lsp-tests/main.lisp`

- **`(deftest lsp-parser …)`** — pure tests on `parse-document`:
  - Empty text → empty diagnostics.
  - Clean `automaton X end` → empty.
  - `automaton X` (no end) → one diagnostic, severity :error, message
    mentions "end".
  - `end` (no automaton) → one diagnostic, "orphan end".
  - Unmatched `{` → one diagnostic at the open brace position.
  - Mismatched bracket pair `({)}` → diagnostic at the bad closer.
  - Multiple errors in one file → multiple diagnostics, each with
    correct line/column.

- **`(deftest lsp-symbols …)`** — pure tests on `scan-symbols`:
  - `automaton sys` → symbol-info {name="sys", kind=:automaton}.
  - `loc cool:` inside an automaton → kind=:location.
  - `contr_var: x, y;` → two :var symbols, names "x" and "y".
  - `synclabs: tau, tick;` → two :sync symbols.
  - Top-level `pc := 0.5;` → kind=:scalar.
  - Top-level `bad = sys.{cool & x >= 20};` → kind=:region.
  - Top-level `reg = sys.reachable;` → kind=:region.
  - Top-level `check = sys.is_reachable(bad);` → kind=:region.
  - User binding inside an `automaton…end` block → NOT collected as
    user binding (top-level only).

- **`(deftest lsp-completion …)`** — pure tests on `complete-at`:
  - Plain prefix `"co"` → contains "cool", "cond1", "contr_var"
    (filtered).
  - Plain prefix at file start, no symbols → keywords only.
  - After `"sys."` where sys is :automaton kind → returns
    +automaton-methods+, NOT keywords or user names.
  - After `"bad."` where bad is :region kind → returns `("print")`.
  - After `"pc."` where pc is :scalar kind → returns `()`.
  - After `"unknown."` → returns `()`.
  - Mid-line cursor (offset in middle of an identifier) → uses
    prefix up to cursor.

### Manual end-to-end smoke (Task 8 of the plan)

1. Open `examples/cycler.pha` in lem.
2. Confirm a `*Messages*` (or lsp-log) entry mentions phaverlite-lsp
   connected.
3. Delete the trailing `end` of the automaton — squiggle appears on
   the `automaton` line within ~1s, severity error.
4. Restore. Squiggle clears.
5. Add a fresh `automaton sys2 end`. Start typing `sys2.` → completion
   menu shows `add_label`, `set_partition_constraints`, etc.
6. Type `bad.` → menu shows just `print`.
7. Type `pc.` → no completions.
8. Type `co` → menu shows `cool`, `cond1`, `contr_var` etc.

### Pass criteria for E

- `bin/test-mode` exits 0 with both suites green.
- Manual smoke checks pass.
- `bin/verify-isolation` PASS.

## Files added

```
phaverlite-lsp.asd                                                 new
lsp/parser.lisp                                                    new
lsp/symbols.lisp                                                   new
lsp/completion.lisp                                                new
lsp/server.lisp                                                    new
lsp/main.lisp                                                      new
phaverlite-mode-lsp.asd                                            new
src-lsp/spec.lisp                                                  new
phaverlite-lsp-tests.asd                                           new
lsp-tests/main.lisp                                                new
bin/phaverlite-lsp                                                 new (executable)
docs/superpowers/specs/2026-05-09-sub-project-e-design.md          (this file)
```

## Files modified

```
config/init.lisp           +1 line: (ql:quickload :phaverlite-mode-lsp …)
bin/test-mode              +1 sbcl invocation for phaverlite-lsp-tests
qlfile                     possibly +1 line for cl-ppcre if not transitively
                            present (verify after first qlot install)
```

## After E

`bin/build-image` rebuilds `var/lem.core` to bake `phaverlite-mode-lsp`
into the image. Day-to-day launches stay sub-second. Opening a `.pha`
file gives the full toolset:

- `C-c C-c` — run phaverlite, stdout to `*phaverlite-output*` (B)
- `C-c C-s` — sweep, fill `*phaverlite-sweep*` row by row (C)
- `C-c C-n` / `C-c C-k` — skip / kill sweep (C)
- `C-c C-p` — plot the current `.pha` (D)
- `p` on a sweep row — plot that row's reach-set (D)
- Live syntax-error squiggles + keyword/symbol/method autocomplete (E)

E completes the A→B→(C,D,E) decomposition. Future enhancements that
build on E: hover, go-to-definition, document symbols (outline view),
scope-aware symbol tracking, semantic highlighting via LSP, image
dumping for sub-second server startup.
