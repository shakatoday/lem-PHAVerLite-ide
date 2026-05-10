;;;; src-lsp/debug-trace.lisp — TEMPORARY instrumentation to find why
;;;; lem-lsp-mode silently drops requests after we add hoverProvider.
;;;;
;;;; Wraps lem-language-client/request:coerce-response and logs every
;;;; conversion: the response method type, the raw response shape, and
;;;; whether convert-from-json succeeded or errored. Output goes to
;;;; var/log/lem-lsp-trace.log relative to lem's current dir.
;;;;
;;;; Remove this file (and remove from .asd :components) once the
;;;; root cause is fixed.

(defpackage #:phaverlite-mode-lsp/debug-trace
  (:use #:cl))
(in-package #:phaverlite-mode-lsp/debug-trace)

(defvar *log-path*
  (merge-pathnames "var/log/lem-lsp-trace.log" (uiop:getcwd)))

(defun log-line (fmt &rest args)
  (handler-case
      (with-open-file (out *log-path*
                           :direction :output
                           :if-exists :append
                           :if-does-not-exist :create)
        (apply #'format out fmt args)
        (terpri out)
        (force-output out))
    (error () nil)))

(ensure-directories-exist *log-path*)
(with-open-file (out *log-path*
                     :direction :output
                     :if-exists :supersede
                     :if-does-not-exist :create)
  (format out "=== lem-lsp debug-trace started ~A ===~%"
          (multiple-value-list (get-decoded-time))))

;; Redefine coerce-response with logging. Original:
;;   (defun coerce-response (request response)
;;     (convert-from-json response (request-message-result request)))
(in-package #:lem-language-client/request)

(defun coerce-response (request response)
  (let ((method (lem-lsp-base/type::request-message-method request))
        (result-type (request-message-result request)))
    (phaverlite-mode-lsp/debug-trace::log-line
     "coerce-response: method=~A type=~A response-class=~A keys=~A"
     method result-type (type-of response)
     (when (hash-table-p response)
       (alexandria:hash-table-keys response)))
    (handler-case
        (let ((value (convert-from-json response result-type)))
          (phaverlite-mode-lsp/debug-trace::log-line
           "  -> success, value class=~A"
           (type-of value))
          value)
      (error (e)
        (phaverlite-mode-lsp/debug-trace::log-line
         "  -> ERROR ~A: ~A" (type-of e) e)
        (error e)))))

;; Tap outgoing wire bytes from lem-stdio-transport to see what lem
;; actually sends (and when).
(in-package #:lem-lsp-mode/lem-stdio-transport)

(defmethod send-message-using-transport :before
    ((transport lem-stdio-transport) connection message)
  (declare (ignore connection))
  (let ((json (with-output-to-string (s) (yason:encode message s))))
    (phaverlite-mode-lsp/debug-trace::log-line
     "[wire->] ~A" json)))

;; Wrap connect-and-initialize's post-init continuation chain with step logs.
(in-package #:lem-lsp-mode/lsp-mode)

(defun connect-and-initialize (workspace buffer continuation)
  (let ((spinner (lem/loading-spinner:start-loading-spinner
                  :modeline
                  :loading-message "initializing"
                  :buffer buffer)))
    (connect (workspace-client workspace)
             (lambda ()
               (phaverlite-mode-lsp/debug-trace::log-line
                "[lsp-trace] connect callback fired")
               (initialize-workspace
                workspace
                (lambda (workspace)
                  (phaverlite-mode-lsp/debug-trace::log-line
                   "[lsp-trace] post-init: BEGIN")
                  (handler-case
                      (progn
                        (phaverlite-mode-lsp/debug-trace::log-line
                         "[lsp-trace] post-init: add-workspace")
                        (add-workspace workspace)
                        (phaverlite-mode-lsp/debug-trace::log-line
                         "[lsp-trace] post-init: set-trigger-characters")
                        (set-trigger-characters workspace)
                        (phaverlite-mode-lsp/debug-trace::log-line
                         "[lsp-trace] post-init: add-buffer-hooks")
                        (add-buffer-hooks buffer)
                        (phaverlite-mode-lsp/debug-trace::log-line
                         "[lsp-trace] post-init: continuation (did-open)")
                        (when continuation (funcall continuation))
                        (phaverlite-mode-lsp/debug-trace::log-line
                         "[lsp-trace] post-init: initialized-workspace")
                        (let ((mode (ensure-mode-object
                                     (spec-mode (workspace-spec workspace)))))
                          (initialized-workspace mode workspace))
                        (phaverlite-mode-lsp/debug-trace::log-line
                         "[lsp-trace] post-init: stop spinner + redraw")
                        (lem/loading-spinner:stop-loading-spinner spinner)
                        (redraw-display)
                        (phaverlite-mode-lsp/debug-trace::log-line
                         "[lsp-trace] post-init: END (clean)"))
                    (error (e)
                      (phaverlite-mode-lsp/debug-trace::log-line
                       "[lsp-trace] post-init ERROR ~A: ~A" (type-of e) e)
                      (error e)))))))))
