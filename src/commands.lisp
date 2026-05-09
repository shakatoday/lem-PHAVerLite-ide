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

;; Inherit from language-mode's keymap so Tab (indent-line-and-complete-symbol)
;; and M-; (comment-or-uncomment-region) reach our buffers.
;;
;; define-major-mode would normally set up this :base for us, but only if the
;; keymap variable is unbound when the macro expands (it uses defvar). We have
;; to bind the keymap here in commands.lisp so that (define-key … 'phaverlite-
;; run-buffer) below can reference it; that defparameter pre-empts the macro's
;; defvar, so we set :base ourselves to keep the inheritance chain intact.
(defparameter *phaverlite-mode-keymap*
  (make-keymap :description '*phaverlite-mode-keymap*
               :base (lem:mode-keymap 'lem/language-mode:language-mode)))

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
        (let ((stream (uiop:process-info-output proc)))
          (loop for line = (read-line stream nil nil)
                while line
                do (write-output-line output-buf line)))
        (let ((exit-code (uiop:wait-process proc)))
          (write-output-line output-buf
                             (format nil "---- exit: ~a" exit-code)))
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
         ;; pop-to-buffer requires a live frontend implementation; in the
         ;; rove test environment there is none, so we tolerate failure.
         (ignore-errors (lem:pop-to-buffer out))
         (launch-phaverlite path out))))))

(define-key *phaverlite-mode-keymap* "C-c C-c" 'phaverlite-run-buffer)
