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
    ;; ~F prints "1.0", "0.05" etc. — clean decimal form. princ-to-string on a
    ;; single-float prints "1.0f0" (with the SBCL float-type suffix), which
    ;; phaverlite's parser rejects with "syntax error" on the pc := line.
    (let* ((pc-string (format nil "~F" pc))
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
  "Get-or-create the *phaverlite-sweep* buffer; clear it; activate
   phaverlite-sweep-results-mode (so `p` reaches plot-row); return it."
  (let ((buf (or (lem:get-buffer *output-buffer-name*)
                 (lem:make-buffer *output-buffer-name*))))
    (setf (lem:buffer-read-only-p buf) nil)
    (lem:erase-buffer buf)
    ;; Activate the results mode so the buffer-local p keybind takes
    ;; effect. The mode command sets buffer-major-mode internally.
    (lem:with-current-buffer buf
      (phaverlite-sweep-results-mode))
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

;;; --- sweep state + engine -----------------------------------------------

(defvar *active-sweep* nil
  "SWEEP-STATE struct describing the in-flight sweep, or NIL when idle.
   Mutated only by the engine and the skip/cancel commands.")

(defstruct sweep-state
  template-path
  template-basename                 ; string; used by phaverlite-sweep-plot-row (sub-project D)
  output-path                       ; legacy slot — current per-pc path comes from sweep-output-path
  values                            ; remaining pc values
  total                             ; original count
  done                              ; count of completed values
  current-pc                        ; the value currently running, or NIL
  current-process                   ; uiop process-info, or NIL
  cancel-flag                       ; :skip, :kill, or NIL
  buffer                            ; *phaverlite-sweep* buffer
  timer)                            ; lem timer driving iteration

(defparameter *poll-interval-ms* 50)

(defparameter *sweep-driver* :timer
  "One of :timer (default; poll via lem:start-timer) or :sync (drive the
   loop synchronously by recursively calling sweep-tick with a small
   sleep). The :sync mode exists so the rove suite — which runs under
   `qlot exec sbcl --script` without an editor frame — can drive the
   sweep deterministically without depending on lem's timer-thread
   firing in a headless image.")

(defun sweep-output-path (template-path pc)
  "Where the materialized .pha goes for this pc value:
   var/sweep/<basename>/pc-<formatted-pc>/<basename>.<ext>.
   Each pc gets its own directory so phaverlite's side-effect output
   files (out_reach, out_inv) survive across iterations and can be
   plotted later via phaverlite-sweep-plot-row (sub-project D)."
  (let* ((basename (pathname-name template-path))
         (ext (pathname-type template-path))
         (pc-string (format nil "~F" pc))
         (rel (format nil "var/sweep/~a/pc-~a/~a.~a"
                      basename pc-string basename (or ext "pha"))))
    (merge-pathnames rel (uiop:getcwd))))

(defun start-next-iteration (state)
  "Schedule the next tick of the sweep loop. Under :timer driver, uses
   lem:start-timer for a one-shot poll. Under :sync driver, sleeps the
   poll interval and calls sweep-tick directly (used by tests)."
  (ecase *sweep-driver*
    (:timer
     (setf (sweep-state-timer state)
           (lem:start-timer
            (lem:make-timer (lambda () (sweep-tick state))
                            :name "phaverlite-sweep-tick")
            *poll-interval-ms*)))
    (:sync
     (sleep (/ *poll-interval-ms* 1000.0))
     (sweep-tick state))))

(defun sweep-tick (state)
  "One tick of the sweep loop. Either advances to the next pc value (if
   no current-process), or polls the current process for completion."
  ;; Stop the previous one-shot before doing anything.
  (when (sweep-state-timer state)
    (lem:stop-timer (sweep-state-timer state))
    (setf (sweep-state-timer state) nil))
  (let ((flag (sweep-state-cancel-flag state)))
    (cond
      ;; Kill: terminate, finalize, exit.
      ((eq flag :kill)
       (when (sweep-state-current-process state)
         (ignore-errors
          (uiop:terminate-process (sweep-state-current-process state)))
         (setf (sweep-state-current-process state) nil))
       (finalize-sweep state t))
      ;; Skip: terminate current, mark cancelled row, advance. If there's
      ;; no in-flight pc value (skip raced past an iteration boundary),
      ;; just drop the flag and resume — nothing to cancel.
      ((eq flag :skip)
       (cond
         ((sweep-state-current-pc state)
          (when (sweep-state-current-process state)
            (ignore-errors
             (uiop:terminate-process (sweep-state-current-process state)))
            (setf (sweep-state-current-process state) nil))
          (write-row (sweep-state-buffer state)
                     (sweep-state-current-pc state)
                     :cancelled "--")
          (incf (sweep-state-done state))
          (setf (sweep-state-current-pc state) nil
                (sweep-state-cancel-flag state) nil)
          (start-next-iteration state))
         (t
          (setf (sweep-state-cancel-flag state) nil)
          (start-next-iteration state))))
      ;; Process running: poll for exit.
      ((sweep-state-current-process state)
       (let ((proc (sweep-state-current-process state)))
         (cond
           ((uiop:process-alive-p proc)
            (start-next-iteration state))    ; re-poll next tick
           (t                                  ; process done — read + record
            (let* ((stream (uiop:process-info-output proc))
                   (output (with-output-to-string (s)
                             (loop for line = (read-line stream nil nil)
                                   while line
                                   do (write-line line s))))
                   (result (parse-result output))
                   (cpu (parse-cpu-time output)))
              (uiop:wait-process proc)
              (write-row (sweep-state-buffer state)
                         (sweep-state-current-pc state)
                         result cpu)
              (incf (sweep-state-done state))
              (setf (sweep-state-current-process state) nil
                    (sweep-state-current-pc state) nil)
              (start-next-iteration state))))))
      ;; No process; spawn next pc value or finish.
      ((null (sweep-state-values state))
       (finalize-sweep state nil))
      (t
       (let ((pc (pop (sweep-state-values state))))
         (setf (sweep-state-current-pc state) pc)
         (write-status-line (sweep-state-buffer state)
                            (sweep-state-done state)
                            (sweep-state-total state)
                            (format nil "pc=~a" pc))
         (handler-case
             (let* ((out-path (sweep-output-path
                               (sweep-state-template-path state) pc))
                    (pc-dir (uiop:pathname-directory-pathname out-path)))
               (ensure-directories-exist out-path)
               (materialize-template (sweep-state-template-path state)
                                     out-path pc)
               (let ((proc (uiop:launch-program
                            (list "phaverlite" (namestring out-path))
                            :output :stream :error-output :output
                            :directory pc-dir)))
                 (setf (sweep-state-current-process state) proc)
                 (start-next-iteration state)))
           (error (e)
             ;; Materialization or spawn failure: record an error row,
             ;; abort the sweep cleanly.
             (write-row (sweep-state-buffer state)
                        pc :unknown (format nil "err:~a" e))
             (finalize-sweep state nil))))))))

(defun finalize-sweep (state cancelled-p)
  "Final cleanup: rewrite status to summary, freeze buffer, clear *active-sweep*."
  (when (sweep-state-timer state)
    (lem:stop-timer (sweep-state-timer state))
    (setf (sweep-state-timer state) nil))
  (when (lem:bufferp (sweep-state-buffer state))
    (finalize (sweep-state-buffer state)
              (sweep-state-done state)
              (sweep-state-total state)
              cancelled-p))
  (setf *active-sweep* nil))

(defun run-sweep (template-path start step stop)
  "Public engine entry point. Builds the sweep-state, opens the output
   buffer, writes the header + initial status line, and schedules the
   first iteration tick. Returns the sweep-state."
  (let* ((values (generate-range start step stop))
         (total (length values))
         (basename (pathname-name template-path))
         (buf (ensure-sweep-buffer))
         (state (make-sweep-state
                 :template-path template-path
                 :template-basename basename
                 :output-path nil
                 :values values
                 :total total
                 :done 0
                 :current-pc nil
                 :current-process nil
                 :cancel-flag nil
                 :buffer buf
                 :timer nil)))
    (write-header buf template-path start step stop total)
    (write-status-line buf 0 total "starting…")
    ;; Stash the basename on a buffer-local var so phaverlite-sweep-plot-row
    ;; (sub-project D) can find the per-pc dirs after *active-sweep* is
    ;; cleared on finalize.
    (setf (lem:buffer-value buf 'phaverlite-sweep-template-basename) basename)
    ;; pop-to-buffer requires a live frontend; tolerate failure in headless
    ;; rove env (same hack as phaverlite-run-buffer in src/commands.lisp).
    (ignore-errors (lem:pop-to-buffer buf))
    (setf *active-sweep* state)
    (start-next-iteration state)
    state))

;;; --- interactive commands -----------------------------------------------

(defparameter *last-sweep-args* nil
  "List (start step stop) from the last successful sweep, used to prefill
   the next minibuffer prompt. NIL means use the default 3.0 -0.05 1.0.")

(defun parse-sweep-args (input)
  "Parse a 'start step stop' string into three floats. Raises ERROR on
   any non-numeric token or wrong arity. Error messages are intentionally
   generic — the user's input is not echoed back verbatim."
  (let ((tokens (remove-if (lambda (s) (zerop (length s)))
                           (uiop:split-string input
                                              :separator '(#\space #\tab)))))
    (unless (= 3 (length tokens))
      (error "Need exactly 3 numbers"))
    (mapcar (lambda (tok)
              (let ((n (handler-case
                           (with-input-from-string (s tok) (read s))
                         (error () (error "Not a number")))))
                (unless (realp n) (error "Not a number"))
                (coerce n 'float)))
            tokens)))

(define-command phaverlite-sweep-buffer (&optional buffer) ()
  "Sweep the __PC__ placeholder in the current .pha buffer over a range
   of values. Prompts for 'start step stop'. Refuses if a sweep is
   already in progress, the buffer is not visiting a file, or the file
   lacks __PC__. Same buffer-modified prompt as phaverlite-run-buffer."
  (let* ((buf (or buffer (lem:current-buffer)))
         (path (lem:buffer-filename buf)))
    (cond
      (*active-sweep*
       (lem:message "Sweep already in progress (use C-c C-k to cancel)"))
      ((null path)
       (lem:message "Buffer not visiting a file"))
      ((not (search "__PC__" (uiop:read-file-string path)))
       (lem:message "No __PC__ placeholder in ~a" path))
      ((and (lem:buffer-modified-p buf)
            (not (lem:prompt-for-y-or-n-p
                  "Buffer modified. Save and run sweep?")))
       nil)
      (t
       (when (lem:buffer-modified-p buf)
         (lem:save-buffer buf))
       (let* ((default (or *last-sweep-args* '(3.0 -0.05 1.0)))
              (default-string (format nil "~a ~a ~a"
                                      (first default)
                                      (second default)
                                      (third default)))
              (input (lem:prompt-for-string
                      "Sweep PC (start step stop): "
                      :initial-value default-string)))
         (handler-case
             (destructuring-bind (start step stop) (parse-sweep-args input)
               (setf *last-sweep-args* (list start step stop))
               (run-sweep path start step stop))
           (error (e)
             (lem:message "Bad input: ~a" e))))))))

(define-command phaverlite-sweep-skip () ()
  "Skip the currently-running pc value in the active sweep. Marks the
   row (cancelled), advances to the next value. No-op if no sweep
   running."
  (cond
    ((null *active-sweep*)
     (lem:message "No phaverlite-sweep in progress"))
    (t
     (setf (sweep-state-cancel-flag *active-sweep*) :skip)
     (lem:message "Skipping current pc value…"))))

(define-command phaverlite-sweep-cancel () ()
  "Kill the active sweep entirely. Stops the loop after terminating the
   in-flight phaverlite. No-op if no sweep running."
  (cond
    ((null *active-sweep*)
     (lem:message "No phaverlite-sweep in progress"))
    (t
     (setf (sweep-state-cancel-flag *active-sweep*) :kill)
     (lem:message "Cancelling sweep…"))))

;;; --- mode keymap bindings ------------------------------------------------
;;;
;;; Per option (d) of Task 8 in the plan: bindings live here, NOT in
;;; src/commands.lisp. Reason: the asd loads sweep.lisp AFTER commands.lisp,
;;; so commands.lisp's reader can't resolve phaverlite-sweep-* symbols at
;;; compile time. The keymap defparameter is exported from
;;; phaverlite-mode/commands and exists by the time sweep.lisp loads.

(define-key phaverlite-mode/commands:*phaverlite-mode-keymap*
            "C-c C-s" 'phaverlite-sweep-buffer)
(define-key phaverlite-mode/commands:*phaverlite-mode-keymap*
            "C-c C-n" 'phaverlite-sweep-skip)
(define-key phaverlite-mode/commands:*phaverlite-mode-keymap*
            "C-c C-k" 'phaverlite-sweep-cancel)

;;; --- *phaverlite-sweep* buffer mode + keymap ----------------------------

(defparameter *phaverlite-sweep-results-mode-keymap*
  (lem:make-keymap :description '*phaverlite-sweep-results-mode-keymap*))

(lem:define-major-mode phaverlite-sweep-results-mode nil
    (:name "PHAVer-sweep"
     :keymap *phaverlite-sweep-results-mode-keymap*)
  (setf (lem:variable-value 'lem:enable-syntax-highlight) nil))
