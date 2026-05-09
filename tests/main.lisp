;;;; tests/main.lisp — rove suite for phaverlite-mode.

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
  (testing "line after 'automaton …' indents +4"
    (ok (= 4 (expected-indent (format nil "automaton heater~%contr_var: t;") 1))))
  (testing "line after a ': '-terminated header indents +4"
    (ok (= 4 (expected-indent (format nil "loc cool:~%  while x >= 18") 1))))
  (testing "line starting with 'end' dedents one step from previous indent"
    (ok (= 0 (expected-indent (format nil "    while x >= 18~%end") 1))))
  (testing "blank previous line falls back to nearest non-blank"
    (ok (= 4 (expected-indent (format nil "loc cool:~%~%  wait { x' == -0.1*x }") 2)))))

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
