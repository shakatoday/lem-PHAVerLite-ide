;;;; config/init.lisp — PHAVerLite IDE bootstrap, sub-project A.
;;;; Loaded by bin/phaverlite-ide via `sbcl --no-userinit --no-sysinit --load`.
;;;; Job: prove the launcher boots lem-ncurses with our config and nothing else.

(in-package #:cl-user)

;; Tell CFFI where to find native libs we built ourselves (see bin/build-deps).
;; Must happen BEFORE (ql:quickload :lem-ncurses) — async-process loads its
;; .dylib at compile time, so the search path needs to be set first.
;; The PHAVERLITE_IDE_LIB env var is set by bin/phaverlite-ide; we read it
;; rather than hardcoding the repo path so this file stays portable.
(ql:quickload :cffi :silent t)
(let ((libdir (uiop:getenv "PHAVERLITE_IDE_LIB")))
  (when (and libdir (not (zerop (length libdir))))
    (pushnew (uiop:ensure-directory-pathname libdir)
             cffi:*foreign-library-directories*
             :test #'equal)))

(ql:quickload :lem-ncurses :silent t)

;; Register the repo root as an ASDF source so (ql:quickload :phaverlite-mode)
;; finds phaverlite-mode.asd. uiop:getcwd is the launcher's cd target — the
;; bin/phaverlite-ide script does `cd "$REPO"` before exec'ing sbcl.
(pushnew (truename (uiop:getcwd)) asdf:*central-registry* :test #'equal)
(ql:quickload :phaverlite-mode :silent t)
(ql:quickload :phaverlite-mode-lsp :silent t)

;; Verification banner — appears in *Messages* so we can confirm THIS init.lisp
;; ran (vs. some stray ~/.config/lem/init.lisp). Used by bin/verify-isolation.
(defparameter *phaverlite-ide-banner*
  "[phaverlite-ide] sub-project A bootstrap loaded")

;; Defer the message until lem is up, then start the editor.
(lem:add-hook lem:*after-init-hook*
              (lambda () (lem:message *phaverlite-ide-banner*)))

(lem:lem)

;; (lem:lem) returns when the user quits lem; without this, SBCL would drop
;; into its REPL and keep the launcher hung. Make the launcher behave like
;; a normal program: shell prompt → C-x C-c in lem → back to shell prompt.
(uiop:quit 0)
