;;;; tests/main.lisp — rove suite for phaverlite-mode.

#+sbcl (require :sb-posix)

(defpackage #:phaverlite-mode/tests
  (:use #:cl #:rove))
(in-package #:phaverlite-mode/tests)

(deftest scaffolding-loads
  (testing "phaverlite-mode package exists after loading the test system"
    (ok (find-package :phaverlite-mode)))
  (testing "all sub-packages exist"
    (ok (find-package :phaverlite-mode/syntax))
    (ok (find-package :phaverlite-mode/indent))
    (ok (find-package :phaverlite-mode/commands))))

(defun face-at (text position)
  "Insert TEXT into a fresh buffer with the phaverlite syntax table,
   run a syntax scan, and return the value of the :attribute text property
   at POSITION (0-based char offset). Returns NIL if no attribute."
  (let* ((buf (lem:make-buffer "*syntax-test*" :temporary t))
         (point (lem:buffer-point buf)))
    (setf (lem:buffer-syntax-table buf)
          phaverlite-mode/syntax:*phaverlite-syntax-table*)
    (setf (lem:variable-value 'lem:enable-syntax-highlight :buffer buf) t)
    (lem:erase-buffer buf)
    (lem:insert-string point text)
    ;; Force a full syntax scan over the buffer.
    (lem:syntax-scan-region (lem:buffer-start-point buf)
                            (lem:buffer-end-point buf))
    (lem:character-offset (lem:buffer-start-point buf) position)
    (lem:text-property-at (lem:buffer-start-point buf) :attribute position)))

(deftest syntax
  (testing "block keyword 'automaton' uses the block face"
    (let ((attr (face-at "automaton heater" 0)))
      (ok (eq attr 'phaverlite-mode/syntax:syntax-keyword-block-attribute))))
  (testing "block keyword 'end' uses the block face"
    (let ((attr (face-at "end" 0)))
      (ok (eq attr 'phaverlite-mode/syntax:syntax-keyword-block-attribute))))
  (testing "regular keyword 'while' uses the stock keyword face"
    (let ((attr (face-at "while x >= 18" 0)))
      (ok (eq attr 'lem:syntax-keyword-attribute))))
  (testing "// line comment uses the comment face"
    (let ((attr (face-at "// hello" 0)))
      (ok (eq attr 'lem:syntax-comment-attribute))))
  (testing "/* block comment */ uses the comment face"
    (let ((attr (face-at "/* hi */" 0)))
      (ok (eq attr 'lem:syntax-comment-attribute)))))

(defun expected-indent (text line-index)
  "Make a fresh buffer holding TEXT, move point to the start of the
   LINE-INDEX'th line (0-based), and call calc-indent. Returns the
   integer column the line should start at."
  (let* ((buf (lem:make-buffer "*indent-test*" :temporary t))
         (point (lem:buffer-point buf)))
    (lem:erase-buffer buf)
    (lem:insert-string point text)
    (lem:move-to-line point (1+ line-index))
    (lem:line-start point)
    (phaverlite-mode/indent:calc-indent point)))

(deftest indent
  (testing "top of file indents to 0"
    (ok (= 0 (expected-indent "automaton heater" 0))))
  (testing "section keyword after 'automaton' indents +4"
    (ok (= 4 (expected-indent (format nil "automaton heater~%contr_var: t;") 1))))
  (testing "statement after 'loc … :' header indents +4 from loc"
    (ok (= 4 (expected-indent (format nil "loc cool:~%  while x >= 18") 1))))
  (testing "'end' aligns with the enclosing automaton (column 0 here)"
    (ok (= 0 (expected-indent (format nil "automaton heater~%    loc cool:~%        do … goto cool;~%end") 3))))
  (testing "blank previous line falls back to nearest non-blank anchor"
    (ok (= 4 (expected-indent (format nil "loc cool:~%~%  wait { x' == -0.1*x }") 2))))
  (testing "second 'loc' is at automaton-level, NOT nested in the previous loc body"
    (ok (= 4 (expected-indent
              (format nil
                      "automaton heater~%    loc cool:~%        do … goto heat;~%    loc heat:")
              3))))
  (testing "'initially:' is at automaton-level, NOT nested in the loc above"
    (ok (= 4 (expected-indent
              (format nil
                      "automaton heater~%    loc cool:~%        do … goto cool;~%    initially: cool & x == 22;")
              3))))
  (testing "statement after 'end' returns to top level (0)"
    (ok (= 0 (expected-indent
              (format nil "automaton heater~%end~%heater.add_label(tau);")
              2))))
  (testing "statement inside a deeply nested loc body uses loc column + 4"
    ;; loc at column 4 → body at column 8, regardless of how many statement
    ;; lines are between the loc header and the current line.
    (ok (= 8 (expected-indent
              (format nil "automaton heater~%    loc cool:~%        wait { … }~%        when x <= 19~%        do { … } goto heat;~%        ")
              5)))))

(defun with-stubbed-prompt (answer thunk)
  "Run THUNK with lem:prompt-for-y-or-n-p stubbed to return ANSWER (T or NIL).
   LEM-CORE is package-locked, so we suppress that lock for the swap."
  (let ((original (fdefinition 'lem:prompt-for-y-or-n-p)))
    (unwind-protect
         (progn
           #+sbcl (sb-ext:without-package-locks
                    (setf (fdefinition 'lem:prompt-for-y-or-n-p)
                          (lambda (&rest args) (declare (ignore args)) answer)))
           #-sbcl (setf (fdefinition 'lem:prompt-for-y-or-n-p)
                        (lambda (&rest args) (declare (ignore args)) answer))
           (funcall thunk))
      #+sbcl (sb-ext:without-package-locks
               (setf (fdefinition 'lem:prompt-for-y-or-n-p) original))
      #-sbcl (setf (fdefinition 'lem:prompt-for-y-or-n-p) original))))

(defun make-temp-pha-buffer (&key modified)
  "Create a buffer visiting a temp .pha file, optionally in modified state."
  (let* ((path (merge-pathnames
                (format nil "phaverlite-test-~a.pha" (get-universal-time))
                (uiop:temporary-directory))))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (write-string "automaton t end" s))
    (let* ((buf (lem:find-file-buffer path)))
      (when modified
        (lem:insert-string (lem:buffer-point buf) " "))
      (values buf path))))

(deftest prompt
  (testing "modified buffer + 'no' aborts without saving"
    (multiple-value-bind (buf path) (make-temp-pha-buffer :modified t)
      (declare (ignore path))
      (with-stubbed-prompt nil
        (lambda ()
          (phaverlite-mode/commands:phaverlite-run-buffer buf)))
      (ok (lem:buffer-modified-p buf) "buffer is still modified")))
  (testing "modified buffer + 'yes' saves the buffer"
    (multiple-value-bind (buf path) (make-temp-pha-buffer :modified t)
      (declare (ignore path))
      (with-stubbed-prompt t
        (lambda ()
          (phaverlite-mode/commands:phaverlite-run-buffer buf)))
      (ng (lem:buffer-modified-p buf) "buffer is no longer modified"))))

(deftest run-command
  (testing "writes 'FAKE OUTPUT <path>' header line and exit:0 footer"
    (multiple-value-bind (buf path) (make-temp-pha-buffer :modified nil)
      (declare (ignore path))
      (with-stubbed-prompt t
        (lambda ()
          (phaverlite-mode/commands:phaverlite-run-buffer buf)))
      (let* ((out (lem:get-buffer "*phaverlite-output*"))
             (text (lem:points-to-string
                    (lem:buffer-start-point out)
                    (lem:buffer-end-point out)))
             (resolved-path (namestring (lem:buffer-filename buf))))
        (ok (search (format nil "FAKE OUTPUT ~a" resolved-path) text))
        (ok (search "---- exit: 0" text))))))

(deftest sweep-parse
  (testing "'bad is reachable' → :reachable"
    (ok (eq :reachable
            (phaverlite-mode/sweep::parse-result "bad is reachable"))))
  (testing "'bad not reachable' → :unreachable"
    (ok (eq :unreachable
            (phaverlite-mode/sweep::parse-result "bad not reachable"))))
  (testing "different region name 'target is reachable' → :reachable"
    (ok (eq :reachable
            (phaverlite-mode/sweep::parse-result "target is reachable"))))
  (testing "different region name 'unsafe not reachable' → :unreachable"
    (ok (eq :unreachable
            (phaverlite-mode/sweep::parse-result "unsafe not reachable"))))
  (testing "neither phrase → :unknown"
    (ok (eq :unknown
            (phaverlite-mode/sweep::parse-result "garbage output"))))
  (testing "both phrases — 'not reachable' wins (sweep_pc.sh precedence)"
    (ok (eq :unreachable
            (phaverlite-mode/sweep::parse-result
             (format nil "bad is reachable~%bad not reachable")))))
  (testing "parse-cpu-time picks penultimate field of LAST 'Time in get_reach_set' line"
    (let ((output (format nil
                          "Time in get_reach_set : 0.10 s~%~
                           Time in get_reach_set : 0.42 s")))
      (ok (string= "0.42"
                   (phaverlite-mode/sweep::parse-cpu-time output)))))
  (testing "parse-cpu-time → NIL when no such line"
    (ok (null (phaverlite-mode/sweep::parse-cpu-time "no timing here")))))

(deftest sweep-range
  (testing "(3.0 -0.05 1.0) produces 41 values starting 3.0 ending 1.0"
    (let ((r (phaverlite-mode/sweep::generate-range 3.0 -0.05 1.0)))
      (ok (= 41 (length r)))
      (ok (= 3.0 (first r)))
      ;; Floating-point: last value should be within step of 1.0.
      (ok (< (abs (- 1.0 (car (last r)))) 1.0e-6))))
  (testing "(1.0 0.5 3.0) produces 5 values"
    (let ((r (phaverlite-mode/sweep::generate-range 1.0 0.5 3.0)))
      (ok (= 5 (length r)))
      (ok (= 1.0 (first r)))
      (ok (= 3.0 (car (last r))))))
  (testing "start = stop produces a single-element list"
    (let ((r (phaverlite-mode/sweep::generate-range 2.0 0.5 2.0)))
      (ok (= 1 (length r)))
      (ok (= 2.0 (first r)))))
  (testing "step = 0 raises an error"
    (ok (signals (phaverlite-mode/sweep::generate-range 1.0 0.0 3.0))))
  (testing "sign-mismatched step raises (start=3 step=+0.5 stop=1)"
    (ok (signals (phaverlite-mode/sweep::generate-range 3.0 0.5 1.0))))
  (testing "sign-mismatched step raises (start=1 step=-0.5 stop=3)"
    (ok (signals (phaverlite-mode/sweep::generate-range 1.0 -0.5 3.0)))))

(deftest sweep-materialize
  (testing "writes substituted template to output path"
    (let* ((tmpl-path (merge-pathnames "phaverlite-tmpl.pha"
                                       (uiop:temporary-directory)))
           (out-path  (merge-pathnames "phaverlite-out.pha"
                                       (uiop:temporary-directory))))
      (with-open-file (s tmpl-path :direction :output :if-exists :supersede)
        (write-string "pc := __PC__;" s))
      (phaverlite-mode/sweep::materialize-template tmpl-path out-path 1.25)
      (ok (string= "pc := 1.25;"
                   (uiop:read-file-string out-path)))))
  (testing "single-float 1.0 substitutes as '1.0' (no f0 type suffix)"
    ;; Regression: princ-to-string on a single-float prints '1.0f0' under
    ;; the SBCL default reader settings used by qlot/lem load chain, which
    ;; phaverlite's parser rejects with 'syntax error' on the pc := line.
    ;; materialize-template must use ~F (or otherwise strip the suffix).
    (let* ((tmpl-path (merge-pathnames "phaverlite-onef.pha"
                                       (uiop:temporary-directory)))
           (out-path  (merge-pathnames "phaverlite-onef-out.pha"
                                       (uiop:temporary-directory))))
      (with-open-file (s tmpl-path :direction :output :if-exists :supersede)
        (write-string "pc := __PC__;" s))
      (phaverlite-mode/sweep::materialize-template tmpl-path out-path 1.0)
      (ok (string= "pc := 1.0;" (uiop:read-file-string out-path)))))
  (testing "raises when template lacks __PC__"
    (let* ((tmpl-path (merge-pathnames "phaverlite-bad.pha"
                                       (uiop:temporary-directory)))
           (out-path  (merge-pathnames "phaverlite-bad-out.pha"
                                       (uiop:temporary-directory))))
      (with-open-file (s tmpl-path :direction :output :if-exists :supersede)
        (write-string "no placeholder here" s))
      (ok (signals
              (phaverlite-mode/sweep::materialize-template
               tmpl-path out-path 1.0))))))

(deftest sweep-render
  (testing "write-header inserts 3 lines: shebang-style, range, status"
    (let* ((buf (lem:make-buffer "*sweep-test*" :temporary t)))
      (lem:erase-buffer buf)
      (phaverlite-mode/sweep::write-header
       buf "Lab3/heater_template.pha" 3.0 -0.05 1.0 41)
      (let ((text (lem:points-to-string (lem:buffer-start-point buf)
                                         (lem:buffer-end-point buf))))
        (ok (search "phaverlite-sweep Lab3/heater_template.pha" text))
        (ok (search "start=3.0" text))
        (ok (search "step=-0.05" text))
        (ok (search "stop=1.0" text))
        (ok (search "(41 values)" text)))))
  (testing "write-status-line rewrites line 3 in place (only one status line)"
    (let* ((buf (lem:make-buffer "*sweep-test*" :temporary t)))
      (lem:erase-buffer buf)
      (phaverlite-mode/sweep::write-header
       buf "x.pha" 1.0 0.5 3.0 5)
      (phaverlite-mode/sweep::write-status-line buf 0 5 "starting…")
      (phaverlite-mode/sweep::write-status-line buf 2 5 "pc=1.5")
      (let ((text (lem:points-to-string (lem:buffer-start-point buf)
                                         (lem:buffer-end-point buf))))
        ;; The starting message must NOT remain.
        (ok (not (search "starting…" text)))
        (ok (search "[2/5 done]" text))
        (ok (search "current: pc=1.5" text)))))
  (testing "write-row appends a column-aligned row below the table separator"
    (let* ((buf (lem:make-buffer "*sweep-test*" :temporary t)))
      (lem:erase-buffer buf)
      (phaverlite-mode/sweep::write-header
       buf "x.pha" 3.0 -0.05 1.0 41)
      (phaverlite-mode/sweep::write-status-line buf 0 41 "pc=3.0")
      (phaverlite-mode/sweep::write-row buf 3.0 :unreachable "0.42")
      (let ((text (lem:points-to-string (lem:buffer-start-point buf)
                                         (lem:buffer-end-point buf))))
        (ok (search "3.0" text))
        (ok (search "unreachable" text))
        (ok (search "0.42" text)))))
  (testing "write-row formats single-float pc as '3.0', NOT '3.0f0'"
    ;; Regression: princ-to-string / ~A on a single-float emits the
    ;; SBCL type suffix; downstream consumers (the dir name in
    ;; sweep-output-path, and phaverlite-sweep-plot-row's lookup) use
    ;; ~F formatting and the row text MUST match or the lookup fails.
    (let* ((buf (lem:make-buffer "*sweep-test*" :temporary t)))
      (lem:erase-buffer buf)
      (phaverlite-mode/sweep::write-header
       buf "x.pha" 3.0 -0.05 1.0 41)
      (phaverlite-mode/sweep::write-row buf 3.0 :unreachable "0.42")
      (let ((text (lem:points-to-string (lem:buffer-start-point buf)
                                         (lem:buffer-end-point buf))))
        (ng (search "3.0f0" text) "no float-type suffix in row pc column"))))
  (testing "finalize rewrites status line to summary"
    (let* ((buf (lem:make-buffer "*sweep-test*" :temporary t)))
      (lem:erase-buffer buf)
      (phaverlite-mode/sweep::write-header
       buf "x.pha" 3.0 -0.05 1.0 41)
      (phaverlite-mode/sweep::write-status-line buf 8 41 "pc=2.65")
      (phaverlite-mode/sweep::finalize buf 8 41 t)
      (let ((text (lem:points-to-string (lem:buffer-start-point buf)
                                         (lem:buffer-end-point buf))))
        (ok (search "[8/41 done]" text))
        (ok (search "cancelled by user" text))
        (ok (not (search "current: pc=2.65" text)))))))

(defmacro with-env-vars (bindings &body body)
  "Set the listed (NAME VALUE) env vars for the dynamic extent of BODY,
   restoring prior values on unwind. SBCL-only (uses sb-posix). We have
   our own because sb-ext:with-environment-variables is not available
   on this SBCL build."
  (let ((saved (gensym "SAVED")))
    `(let ((,saved (mapcar (lambda (b)
                             (cons (first b) (uiop:getenv (first b))))
                           ',bindings)))
       (unwind-protect
            (progn
              ,@(loop for b in bindings collect
                      `(sb-posix:setenv ,(first b) ,(second b) 1))
              ,@body)
         (dolist (entry ,saved)
           (if (cdr entry)
               (sb-posix:setenv (car entry) (cdr entry) 1)
               (sb-posix:unsetenv (car entry))))))))

(defun make-temp-pha-template (content)
  "Create a temp .pha file containing CONTENT, return its truename."
  (let ((p (merge-pathnames
            (format nil "phaverlite-sweep-test-~a.pha" (get-universal-time))
            (uiop:temporary-directory))))
    (with-open-file (s p :direction :output :if-exists :supersede)
      (write-string content s))
    (truename p)))

(defun wait-for-sweep-completion (&key (timeout-secs 10))
  "Block until *active-sweep* is NIL or TIMEOUT-SECS elapses. Returns T
   on completion, NIL on timeout."
  (let ((start (get-universal-time)))
    (loop until (or (null phaverlite-mode/sweep::*active-sweep*)
                    (> (- (get-universal-time) start) timeout-secs))
          do (sleep 0.05))
    (null phaverlite-mode/sweep::*active-sweep*)))

(deftest sweep-engine
  (testing "3-value sweep produces 3 rows + finished summary"
    (let ((path (make-temp-pha-template "pc := __PC__;")))
      (with-env-vars
          (("FAKE_PHAVERLITE_MODE" "sweep")
           ("FAKE_RESULT" "unreachable")
           ("FAKE_CPU" "0.42"))
        (let ((phaverlite-mode/sweep::*sweep-driver* :sync))
          (phaverlite-mode/sweep::run-sweep path 3.0 -1.0 1.0))
        (ok (wait-for-sweep-completion)))
      (let* ((buf (lem:get-buffer "*phaverlite-sweep*"))
             (text (lem:points-to-string
                    (lem:buffer-start-point buf)
                    (lem:buffer-end-point buf))))
        (ok (search "[3/3 done]" text))
        (ok (search "finished" text))
        ;; Three result rows.
        (ok (search "3.0" text))
        (ok (search "2.0" text))
        (ok (search "1.0" text))
        ;; All three rows show 'unreachable' and the faked cpu.
        (ok (= 3 (count #\Newline (with-output-to-string (s)
                                    (loop for i from 0
                                          for j = (search "unreachable" text :start2 i)
                                          while j
                                          do (terpri s)
                                             (setf i (1+ j)))))))
        (ok (search "0.42" text)))
      ;; Per-pc dirs were created with the materialized .pha inside, AND
      ;; phaverlite ran with cwd set there (out_reach/out_inv would land
      ;; there too if the fake binary touched them — sub-project D Task 4).
      (let* ((basename (pathname-name path))
             (pc-3-dir (merge-pathnames
                        (format nil "var/sweep/~a/pc-3.0/" basename)
                        (uiop:getcwd))))
        (ok (probe-file (merge-pathnames
                         (format nil "~a.pha" basename) pc-3-dir))
            "per-pc dir contains the materialized .pha"))))
  (testing "*active-sweep* is NIL after completion"
    (ok (null phaverlite-mode/sweep::*active-sweep*)))
  (testing "skip case: cancel-flag :skip marks one row (cancelled), continues"
    (let ((path (make-temp-pha-template "pc := __PC__;")))
      (with-env-vars
          (("FAKE_PHAVERLITE_MODE" "sweep")
           ("FAKE_RESULT" "unreachable")
           ("FAKE_CPU" "0.10")
           ("FAKE_SLEEP" "1"))
        ;; Drive in a worker thread so the test thread can mutate
        ;; cancel-flag while the engine sleeps in :sync mode.
        (let ((thread (bt2:make-thread
                       (lambda ()
                         (let ((phaverlite-mode/sweep::*sweep-driver* :sync))
                           (phaverlite-mode/sweep::run-sweep
                            path 5.0 -1.0 1.0)))
                       :name "sweep-skip-test")))
          ;; Wait until at least one row has been recorded AND a new pc
          ;; is currently in-flight, then request the skip. With the
          ;; fake binary's tiny FAKE_SLEEP, the in-flight window is
          ;; ~1s — plenty of time for this thread to notice.
          (loop with deadline = (+ (get-universal-time) 15)
                until (or (and phaverlite-mode/sweep::*active-sweep*
                               (>= (phaverlite-mode/sweep::sweep-state-done
                                    phaverlite-mode/sweep::*active-sweep*)
                                   1)
                               (phaverlite-mode/sweep::sweep-state-current-pc
                                phaverlite-mode/sweep::*active-sweep*))
                          (> (get-universal-time) deadline))
                do (sleep 0.02))
          (when phaverlite-mode/sweep::*active-sweep*
            (setf (phaverlite-mode/sweep::sweep-state-cancel-flag
                   phaverlite-mode/sweep::*active-sweep*)
                  :skip))
          (bt2:join-thread thread)))
      (ok (null phaverlite-mode/sweep::*active-sweep*))
      (let* ((buf (lem:get-buffer "*phaverlite-sweep*"))
             (text (lem:points-to-string
                    (lem:buffer-start-point buf)
                    (lem:buffer-end-point buf))))
        (ok (search "cancelled" text))
        (ok (search "[5/5 done]" text))
        (ok (search "finished" text)))))
  (testing "kill case: cancel-flag :kill stops at current value, summary"
    (let ((path (make-temp-pha-template "pc := __PC__;")))
      (with-env-vars
          (("FAKE_PHAVERLITE_MODE" "sweep")
           ("FAKE_RESULT" "unreachable")
           ("FAKE_CPU" "0.10")
           ("FAKE_SLEEP" "1"))
        (let ((thread (bt2:make-thread
                       (lambda ()
                         (let ((phaverlite-mode/sweep::*sweep-driver* :sync))
                           (phaverlite-mode/sweep::run-sweep
                            path 5.0 -1.0 1.0)))
                       :name "sweep-kill-test")))
          (loop with deadline = (+ (get-universal-time) 15)
                until (or (and phaverlite-mode/sweep::*active-sweep*
                               (>= (phaverlite-mode/sweep::sweep-state-done
                                    phaverlite-mode/sweep::*active-sweep*)
                                   2))
                          (> (get-universal-time) deadline))
                do (sleep 0.02))
          (when phaverlite-mode/sweep::*active-sweep*
            (setf (phaverlite-mode/sweep::sweep-state-cancel-flag
                   phaverlite-mode/sweep::*active-sweep*)
                  :kill))
          (bt2:join-thread thread)))
      (ok (null phaverlite-mode/sweep::*active-sweep*))
      (let* ((buf (lem:get-buffer "*phaverlite-sweep*"))
             (text (lem:points-to-string
                    (lem:buffer-start-point buf)
                    (lem:buffer-end-point buf))))
        (ok (search "cancelled by user" text))
        ;; Some progress made before kill — done count is in the status
        ;; line as [N/5 done] for some N <= 5.
        (ok (search "[" text))))))

(defun make-temp-plot-dir-with-files (&key (with-reach t) (with-inv t))
  "Create a fresh temp dir with optional out_reach + out_inv files.
   Returns the dir as an absolute pathname."
  (let* ((dir (merge-pathnames
               (format nil "phaverlite-plot-test-~a-~a/"
                       (get-universal-time) (random 1000000))
               (uiop:temporary-directory))))
    (ensure-directories-exist dir)
    (when with-reach
      (with-open-file (s (merge-pathnames "out_reach" dir)
                         :direction :output :if-exists :supersede)
        (write-string "1 2 0
3 4 0
" s)))
    (when with-inv
      (with-open-file (s (merge-pathnames "out_inv" dir)
                         :direction :output :if-exists :supersede)
        (write-string "0 0 0
5 5 0
" s)))
    dir))

(defun stub-message-collector ()
  "Stub lem:message to collect messages into a list. Returns two values:
   (1) a thunk to install the stub, (2) a thunk to read the collected
   list and uninstall."
  (let ((collected '())
        (original (fdefinition 'lem:message)))
    (values
     (lambda ()
       #+sbcl (sb-ext:without-package-locks
                (setf (fdefinition 'lem:message)
                      (lambda (fmt &rest args)
                        (push (apply #'format nil fmt args) collected))))
       #-sbcl (setf (fdefinition 'lem:message)
                    (lambda (fmt &rest args)
                      (push (apply #'format nil fmt args) collected))))
     (lambda ()
       (prog1 (nreverse collected)
         #+sbcl (sb-ext:without-package-locks
                  (setf (fdefinition 'lem:message) original))
         #-sbcl (setf (fdefinition 'lem:message) original))))))

(deftest plot-render
  (testing "both files present → plot.png is written"
    (let ((dir (make-temp-plot-dir-with-files :with-reach t :with-inv t)))
      (multiple-value-bind (install collect) (stub-message-collector)
        (funcall install)
        (let ((result (phaverlite-mode/plot::render-plot-dir dir)))
          (let ((messages (funcall collect)))
            (declare (ignore messages))
            (ok (probe-file (merge-pathnames "plot.png" dir)))
            (ok (truename result))                         ; non-NIL return
            (ok (search "FAKE GRAPH OUTPUT"
                        (uiop:read-file-string
                         (merge-pathnames "plot.png" dir)))))))))
  (testing "out_reach missing → message + return NIL + no plot.png"
    (let ((dir (make-temp-plot-dir-with-files :with-reach nil :with-inv t)))
      (multiple-value-bind (install collect) (stub-message-collector)
        (funcall install)
        (let ((result (phaverlite-mode/plot::render-plot-dir dir)))
          (let ((messages (funcall collect)))
            (ok (null result))
            (ok (some (lambda (m) (search "out_reach" m)) messages))
            (ok (not (probe-file (merge-pathnames "plot.png" dir)))))))))
  (testing "out_inv missing → message + return NIL + no plot.png"
    (let ((dir (make-temp-plot-dir-with-files :with-reach t :with-inv nil)))
      (multiple-value-bind (install collect) (stub-message-collector)
        (funcall install)
        (let ((result (phaverlite-mode/plot::render-plot-dir dir)))
          (let ((messages (funcall collect)))
            (ok (null result))
            (ok (some (lambda (m) (search "out_inv" m)) messages))
            (ok (not (probe-file (merge-pathnames "plot.png" dir))))))))))

(defun make-temp-plot-pha-buffer ()
  "Create a buffer visiting a temp .pha file with arbitrary content
   (the fake phaverlite ignores the file content; what matters is the
   buffer-filename)."
  (let* ((path (merge-pathnames
                (format nil "phaverlite-plot-cmd-~a-~a.pha"
                        (get-universal-time) (random 1000000))
                (uiop:temporary-directory))))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (write-string "automaton t end" s))
    (lem:find-file-buffer path)))

(deftest plot-buffer-command
  (testing "happy path: phaverlite-plot-buffer creates plot.png"
    (let ((buf (make-temp-plot-pha-buffer)))
      (with-env-vars
          (("FAKE_PHAVERLITE_MODE" "plot"))
        (multiple-value-bind (install collect) (stub-message-collector)
          (funcall install)
          (unwind-protect
               (with-stubbed-prompt t
                 (lambda ()
                   (phaverlite-mode/plot:phaverlite-plot-buffer buf)))
            (funcall collect))))
      (let* ((basename (pathname-name (lem:buffer-filename buf)))
             (expected-plot (merge-pathnames
                             (format nil "var/plot/~a/plot.png" basename)
                             (uiop:getcwd))))
        (ok (probe-file expected-plot))
        (ok (search "FAKE GRAPH OUTPUT"
                    (uiop:read-file-string expected-plot))))))
  (testing "refuses when *active-sweep* is non-nil"
    (let ((phaverlite-mode/sweep::*active-sweep*
            (phaverlite-mode/sweep::make-sweep-state
             :template-path "x" :template-basename "x"
             :output-path "x" :values nil :total 0 :done 0
             :current-pc nil :current-process nil
             :cancel-flag nil :buffer nil :timer nil))
          (buf (make-temp-plot-pha-buffer)))
      (multiple-value-bind (install collect) (stub-message-collector)
        (funcall install)
        (phaverlite-mode/plot:phaverlite-plot-buffer buf)
        (let ((messages (funcall collect)))
          (ok (some (lambda (m) (search "Sweep in progress" m)) messages)))))))

(deftest sweep-plot-row
  (testing "after a sweep, p on a row creates plot.png in that pc's dir"
    (let ((path (make-temp-pha-template "pc := __PC__;")))
      (with-env-vars
          (("FAKE_PHAVERLITE_MODE" "sweep")
           ("FAKE_RESULT" "unreachable")
           ("FAKE_CPU" "0.10")
           ("FAKE_TOUCH_REACH_INV" "1"))
        (let ((phaverlite-mode/sweep::*sweep-driver* :sync))
          (phaverlite-mode/sweep::run-sweep path 3.0 -1.0 1.0))
        (ok (wait-for-sweep-completion)))
      (let* ((basename (pathname-name path))
             (pc-3-dir (merge-pathnames
                        (format nil "var/sweep/~a/pc-3.0/" basename)
                        (uiop:getcwd))))
        (ok (probe-file (merge-pathnames "out_reach" pc-3-dir)))
        (ok (probe-file (merge-pathnames "out_inv" pc-3-dir)))
        (let* ((sweep-buf (lem:get-buffer "*phaverlite-sweep*"))
               (point (lem:buffer-point sweep-buf)))
          (lem:move-to-line point 7)         ; first row after header
          (lem:line-start point)
          (lem:with-current-buffer sweep-buf
            (multiple-value-bind (install collect) (stub-message-collector)
              (funcall install)
              (unwind-protect
                   (phaverlite-mode/plot:phaverlite-sweep-plot-row)
                (funcall collect))))
          (ok (probe-file (merge-pathnames "plot.png" pc-3-dir)))))))
  (testing "wrong buffer: message and no-op"
    (let ((scratch (lem:make-buffer "*scratch-test*" :temporary t)))
      (lem:with-current-buffer scratch
        (multiple-value-bind (install collect) (stub-message-collector)
          (funcall install)
          (phaverlite-mode/plot:phaverlite-sweep-plot-row)
          (let ((messages (funcall collect)))
            (ok (some (lambda (m) (search "Not in a *phaverlite-sweep*" m))
                      messages))))))))
