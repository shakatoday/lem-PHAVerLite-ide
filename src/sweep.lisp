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
