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

;; --- temporary LSP capability debug command --------------------------------
;; M-x phaverlite-lsp-debug-caps prints, for the current buffer's LSP
;; workspace: whether server-capabilities is bound, whether
;; completion-provider slot is bound on it, and the trigger-characters.
;; Output goes to *Messages*. Remove once completion is verified working.
(lem:define-command phaverlite-lsp-debug-caps () ()
  (let* ((buffer (lem:current-buffer))
         (workspace
           (handler-case
               (lem-lsp-mode/lsp-mode::buffer-workspace buffer nil)
             (error (e) (lem:message "buffer-workspace ERROR: ~A" e) nil))))
    (cond
      ((null workspace)
       (lem:message "no workspace for buffer (language-id=~A)"
                    (lem-lsp-mode/lsp-mode::buffer-language-id buffer)))
      (t
       (let ((caps (handler-case
                       (lem-lsp-mode/lsp-mode::workspace-server-capabilities workspace)
                     (unbound-slot () :unbound)
                     (error (e) (format nil "ERR: ~A" e)))))
         (cond
           ((eq caps :unbound)
            (lem:message "workspace-server-capabilities slot UNBOUND"))
           ((stringp caps)
            (lem:message "caps access errored: ~A" caps))
           (t
            (let ((cp-bound
                    (slot-boundp caps 'lem-lsp-base/protocol-3-17::completion-provider)))
              (lem:message "caps class=~A completion-provider bound?=~A"
                           (class-name (class-of caps))
                           cp-bound)
              (when cp-bound
                (let* ((cp (lsp:server-capabilities-completion-provider caps))
                       (tc (handler-case
                               (lsp:completion-options-trigger-characters cp)
                             (unbound-slot () :unbound))))
                  (lem:message "  cp class=~A trigger-chars=~A (type=~A)"
                               (class-name (class-of cp))
                               tc (type-of tc))))))))))))
  nil)

(lem:lem)

;; (lem:lem) returns when the user quits lem; without this, SBCL would drop
;; into its REPL and keep the launcher hung. Make the launcher behave like
;; a normal program: shell prompt → C-x C-c in lem → back to shell prompt.
(uiop:quit 0)
