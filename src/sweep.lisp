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
        for i from 0
        for v = (+ start (* i step))
        while (if (minusp step)
                  (>= v (- stop eps))
                  (<= v (+ stop eps)))
        collect v))

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
    (setf (lem:buffer-read-only-p buf) nil)
    (lem:erase-buffer buf)
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
   trailing text after '[done/total done]  ' — typically 'current: pc=<x>'
   during a sweep, or a summary like 'cancelled by user' on finalize."
  (let ((text (format nil "[~a/~a done]  ~a" done total
                      (if (and (stringp current-or-message)
                               (or (search "pc=" current-or-message)
                                   (search "PC=" current-or-message)))
                          (format nil "current: ~a" current-or-message)
                          current-or-message))))
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
