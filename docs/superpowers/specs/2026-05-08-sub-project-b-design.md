# Sub-project B — `phaverlite-mode` (.pha major mode + run stub)

**Date:** 2026-05-08
**Status:** Approved design, not yet implemented
**Scope:** Second of five sub-projects. Builds on sub-project A. See `CLAUDE.md`
for the A→B→(C,D,E) decomposition.

## Goal

Open `.pha` files in lem with PHAVer-aware syntax highlighting, block-aware
indentation, comment toggling, and a single command (`M-x phaverlite-run-buffer`,
bound to `C-c C-c`) that runs `phaverlite` on the current file and shows its
output in a split window below.

After B, the IDE is end-to-end usable for editing one `.pha` and running it,
with no sweep, no plotting, and no LSP. Those are C, D, E.

## Definition of done

1. Opening any `.pha` file via the launcher activates `phaverlite-mode`
   automatically (via `lem:*auto-mode-alist*`).
2. Block keywords (`automaton`, `end`, `loc`) render in a stronger face than
   other keywords (`contr_var`, `synclabs`, `initially`, `while`, `wait`,
   `when`, `sync`, `do`, `goto`). `//` line comments and `/* … */` block
   comments render in the comment face. Numbers and operators get their stock
   faces.
3. Pressing Enter after a line ending in `:` or after a bare `automaton …`
   line places the cursor one step (4 spaces) deeper than the previous
   line's indent. Pressing Tab on a line whose first non-whitespace token
   is `end` re-indents that line one step shallower than the previous
   non-blank line (clamped at column 0). Pressing Tab on any other line
   matches the previous non-blank line's indent. (No "electric" auto-dedent
   while the user is mid-typing `end`; dedent happens on the next Tab.)
4. `M-;` toggles `// ` on the current line/region.
5. Paren matching works for `()`, `{}`, `[]` (free from the syntax-table).
6. `M-x phaverlite-run-buffer` (or `C-c C-c`) on a `.pha` buffer:
   - if the buffer is not visiting a file → message `Buffer not visiting a file`
     and abort;
   - if the buffer is modified → minibuffer prompt
     `Buffer modified. Save and run phaverlite? (y/n)`;
     `n` aborts silently, `y` saves;
   - spawns `phaverlite <path>` asynchronously; opens `*phaverlite-output*` in
     a horizontal split below the source; cursor stays in source; output
     buffer header `$ phaverlite <path>`, footer `---- exit: <code>`.
7. `bin/test-mode` exits 0 (rove suite passes).
8. `bin/verify-isolation` PASS (no new `$HOME` writes from the new mode).

**Out of scope for B:** PC sweep UI (sub-project C), plot generation (D), LSP
diagnostics / symbols / hover (E), `phaverlite` output parsing (C/D parse
"bad reachable" / CPU time; B leaves output as raw text), block-keyword paren
matching (`automaton`/`end` highlighting — YAGNI for the corpus we have),
auto-rerun on save, multiple-extension binding.

## Architecture

One ASDF system. Layout follows lem's convention (`lem.asd` at repo root
with `:pathname "src"`, source files directly under `src/` — no extra
project-name folder). Inline-package style per project convention (no
`package.lisp`, lem-style `/` submodule names):

```
phaverlite-mode.asd              at repo root
                                  (defsystem "phaverlite-mode"
                                    :pathname "src"
                                    :depends-on ("lem")
                                    :serial t
                                    :components ((:file "syntax")
                                                 (:file "indent")
                                                 (:file "commands")
                                                 (:file "mode")))
src/
  syntax.lisp                    package phaverlite-mode/syntax
  indent.lisp                    package phaverlite-mode/indent
  commands.lisp                  package phaverlite-mode/commands
  mode.lisp                      package phaverlite-mode  (top-level, what
                                                           init.lisp loads)
```

Future sub-projects (C `pc-sweep`, D `plot`, E `phaverlite-lsp`) get their
own asd at repo root and their own top-level source folder — mirroring
lem's `extensions/`, `frontends/`, `contrib/` pattern. They do **not** nest
under `src/`.

`config/init.lisp` gains one line after `lem-ncurses` loads, before
`(lem:lem)`:

```lisp
(ql:quickload :phaverlite-mode :silent t)
```

`bin/build-image` rebuilds the lem core after the new system is added; from
then on the mode is baked into `var/lem.core` and launches at the same speed
as bare lem.

A separate test system loads only when running tests; production never sees
rove. Layout follows lem's own convention (`lem-tests.asd` at repo root +
`tests/` directory at repo root):

```
phaverlite-mode-tests.asd       at repo root, NOT under src/
                                 (defsystem "phaverlite-mode-tests"
                                   :depends-on ("phaverlite-mode" "rove")
                                   :pathname "tests"
                                   :components ((:file "main"))
                                   :perform (test-op (op c)
                                              (symbol-call :rove '#:run c)))
tests/                          at repo root
  main.lisp                     package phaverlite-mode/tests
                                 (deftest indent …) (deftest syntax …)
                                 (deftest prompt …) (deftest run-command …)
  fake-phaverlite               executable shell script (test fixture)
```

ASDF requires the primary system name to match the asd filename, so the
system is `phaverlite-mode-tests` (hyphen). The *package* in `tests/main.lisp`
uses our slash convention (`phaverlite-mode/tests`) — system names and
package names are independent in CL, and lem's per-mode test example
(`.claude/rules/testing.md`) uses exactly this form.

## Components

### `syntax.lisp` — `phaverlite-mode/syntax`

- Defines `*phaverlite-syntax-table*` via `lem:make-syntax-table`.
- Comment syntax: `//` line, `/* … */` block.
- Three keyword regex sets registered as syntax-test patterns:
  - **Block:** `automaton|end|loc` → `*syntax-keyword-block-face*`
    (a custom face, bolder than the stock keyword face).
  - **Other:** `contr_var|synclabs|initially|while|wait|when|sync|do|goto`
    → `lem:*syntax-keyword-face*`.
  - **Numbers, operators:** stock number/builtin faces.
- Exports: `*phaverlite-syntax-table*`, `*syntax-keyword-block-face*`.

### `indent.lisp` — `phaverlite-mode/indent`

- `(calc-indent point) → integer`.
- Algorithm:
  1. Walk back to the previous non-blank line.
  2. Base indent = its leading whitespace column count.
  3. If that line ends in `:` or matches `^automaton\b`: base + 4.
  4. If the *current* line starts with `end`: max(base − 4, 0).
  5. Otherwise: base.
- Total function — always returns a non-negative integer; no error path.
- Registered as the mode's `:calc-indent-function`.
- Exports: `calc-indent`.

### `commands.lisp` — `phaverlite-mode/commands`

- `phaverlite-run-buffer` (interactive):
  1. If buffer has no file → `lem:message` "Buffer not visiting a file"; return.
  2. If buffer modified → minibuffer y/n prompt
     `"Buffer modified. Save and run phaverlite? (y/n) "`. `n` returns silently;
     `y` calls `lem:save-current-buffer`.
  3. Open or switch to `*phaverlite-output*` buffer in a horizontal split
     below the source window; clear it; insert
     `$ phaverlite <path>\n----\n`.
  4. `uiop:launch-program (list "phaverlite" path) :output :stream
     :error-output :stream` — async, non-blocking. On `program-error`
     (e.g. command not found): message `phaverlite: command not found on PATH`;
     close output buffer.
  5. A drain timer (lem `lem:start-timer`) reads available bytes from both
     streams into the output buffer until the process exits.
  6. On exit, append `\n---- exit: <code>` footer.
- Mode keymap (`*phaverlite-mode-keymap*`) binds `C-c C-c` →
  `phaverlite-run-buffer`.
- Exports: `phaverlite-run-buffer`, `*phaverlite-mode-keymap*`.

### `mode.lisp` — `phaverlite-mode`

- `(define-major-mode phaverlite-mode lem:fundamental-mode …)` wiring
  syntax-table, `:calc-indent-function 'phaverlite-mode/indent:calc-indent`,
  keymap, `:comment-string "// "`.
- File-extension binding: `(pushnew '("\\.pha\\'" . phaverlite-mode)
  lem:*auto-mode-alist*)`.
- Re-exports `phaverlite-run-buffer` so users can `M-x` it without naming the
  sub-package.

## Data flow

Open path (per keystroke / file open):

```
user opens foo.pha
  → lem looks at *auto-mode-alist*, sees ".pha" → phaverlite-mode
  → mode init: install syntax-table, indent fn, keymap, comment string
  → on every redraw, lem applies syntax-table → faces propagate to screen
  → on Enter / Tab, lem calls calc-indent(point) → moves point to that column
```

Run path:

```
user hits C-c C-c (or M-x phaverlite-run-buffer)
  → check buffer has filename
  → if modified: minibuffer y/n prompt
      n → abort
      y → save buffer to disk
  → uiop:launch-program ("phaverlite" path) :output :stream :error-output :stream
  → open *phaverlite-output* buffer in horizontal split below source
  → write header: "$ phaverlite <path>\n----\n"
  → drain timer reads available bytes into output buffer
  → on process exit, append footer: "\n---- exit: <code>"
  → cursor remains in source buffer
```

## Error handling

| Where | Failure | Policy |
|---|---|---|
| `phaverlite` not on PATH | `uiop:launch-program` raises | Catch; minibuffer message `phaverlite: command not found on PATH`; output buffer closed |
| Run-buffer on a non-file buffer | No filename | Message `Buffer not visiting a file`; no prompt, no run |
| Buffer modified, user answers `n` | — | Silent abort; minibuffer clears |
| `phaverlite` exits non-zero | Process completes | Output buffer kept; footer reads `---- exit: <code>` |
| Mode load fails at boot (e.g. `.asd` broken) | `quickload` raises in `init.lisp` | Lem still launches without `.pha` binding; `*Messages*` shows the backtrace; degraded but functional |

`calc-indent` is total (always returns a non-negative integer); no error path.
Syntax-table application is lem's responsibility; we do not intercept its
errors.

No retry logic. No fallback to a system editor. No "did you mean…?"
suggestions. If `phaverlite` is broken the user fixes their environment.

## Testing

Rove suite, run via:

```sh
bin/test-mode    # zsh launcher; PATH=tests:$PATH; runs (asdf:test-system :phaverlite-mode-tests).
                 # The test asd's :perform delegates to (rove:run …); rove exits 0 on
                 # all-pass, non-zero otherwise; bin/test-mode propagates that exit code.
```

Layout follows lem's convention (`lem-tests.asd` at root + `tests/` at root):

```
phaverlite-mode-tests.asd  at repo root; (defsystem "phaverlite-mode-tests"
                              :depends-on ("phaverlite-mode" "rove")
                              :pathname "tests" :components ((:file "main"))
                              :perform (test-op (op c)
                                         (symbol-call :rove '#:run c)))
tests/
  main.lisp                  package phaverlite-mode/tests; one file with
                              (deftest …) per area
  fake-phaverlite            executable: `echo "FAKE OUTPUT $1"; exit ${FAKE_EXIT:-0}`
qlfile                       + rove
```

`phaverlite-mode-tests` is a separate ASDF system on purpose — production
image (`var/lem.core`) never loads rove.

**Test set:**

- `(deftest indent …)` — fixture strings → `calc-indent` returns expected
  column. Cases: after `:`, after `automaton`, before `end`, blank line,
  file top.
- `(deftest syntax …)` — `lem:text-property-at` over canned source; assert
  face name. Catches keyword-list typos, comment-delimiter regressions,
  regex bugs.
- `(deftest prompt …)` — stub lem's prompt fn → `:yes` / `:no` paths;
  assert save-or-abort.
- `(deftest run-command …)` — temp `.pha`, invoke
  `phaverlite-run-buffer`; assert output buffer contains
  `FAKE OUTPUT <path>` and footer matches `$FAKE_EXIT`. Toggle
  `FAKE_EXIT=1` to test the failure path.

**Eyeball-only:** color distinctness on real terminal, split layout looks
sane, `bin/verify-isolation` PASS. These are perception/integration checks
that no unit test catches anyway.

**Pass criteria for B:** `bin/test-mode` exits 0; `bin/verify-isolation`
PASS; smoke corpus (`Lab3/heater_template.pha`, `Lab3/bouncing_ball.pha`,
the `.pha` model in `ps3/`) opens cleanly with the expected colors and
indent behavior.

## Files added

```
phaverlite-mode.asd                            (at repo root, :pathname "src")
src/syntax.lisp
src/indent.lisp
src/commands.lisp
src/mode.lisp
phaverlite-mode-tests.asd                      (at repo root, lem convention)
tests/main.lisp                                (at repo root, lem convention)
tests/fake-phaverlite                          (executable shell script)
bin/test-mode                                  (executable zsh script)
docs/superpowers/specs/2026-05-08-sub-project-b-design.md   (this file)
```

## Files modified

```
config/init.lisp                +1 line: (ql:quickload :phaverlite-mode :silent t)
qlfile                          +1 line: rove
qlfile.lock                     regenerated by `qlot install`
.gitignore                      no change expected
CLAUDE.md                       no change expected (B is in the planned scope)
```

## After B

`bin/build-image` is re-run once to bake the new mode into `var/lem.core`.
After that, day-to-day launches stay sub-second; opening `.pha` files
gives the full mode immediately.

Sub-project C (`pc-sweep`) lands a sibling system `src/pc-sweep/` that
adds new commands alongside `phaverlite-run-buffer`; B's stub command
stays as the "just run it" path.
