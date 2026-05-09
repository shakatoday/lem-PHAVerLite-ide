;;;; lsp/symbols.lisp — regex-based symbol scanner with kind tracking.

(defpackage #:phaverlite-lsp/symbols
  (:use #:cl)
  (:export #:scan-symbols
           #:symbol-info
           #:make-symbol-info
           #:symbol-info-name
           #:symbol-info-kind
           #:symbol-info-line))
(in-package #:phaverlite-lsp/symbols)

(defstruct symbol-info
  name                  ; string
  kind                  ; :keyword | :automaton | :location | :var | :sync
                        ; | :region | :scalar | :unknown
  line)                 ; 1-based

(defun trim (s)
  (string-trim '(#\space #\tab) s))

(defun split-and-trim (s separator)
  "Split S on SEPARATOR char, trim each piece, drop empties."
  (let ((parts (loop for start = 0 then (1+ end)
                     for end = (position separator s :start start)
                     collect (subseq s start end)
                     while end)))
    (remove-if (lambda (x) (zerop (length x)))
               (mapcar #'trim parts))))

(defun infer-binding-kind (rhs)
  "Inspect the RHS string of a top-level binding (after trimming and
   stripping the trailing ;). Return one of :scalar :region :unknown."
  (let ((r (trim (or rhs ""))))
    ;; Strip trailing semicolon if present.
    (when (and (plusp (length r))
               (char= (char r (1- (length r))) #\;))
      (setf r (trim (subseq r 0 (1- (length r))))))
    (cond
      ;; AUTO.{...}
      ((cl-ppcre:scan "^\\w+\\s*\\.\\s*\\{" r) :region)
      ;; AUTO.reachable / AUTO.get_invariants / AUTO.is_reachable(...)
      ((cl-ppcre:scan "^\\w+\\s*\\.\\s*(reachable|get_invariants|is_reachable\\s*\\()" r)
       :region)
      ;; Looks like a number (with optional sign, decimal, exponent)
      ((cl-ppcre:scan "^[+-]?[0-9]" r) :scalar)
      (t :unknown))))

(defun scan-symbols (text)
  "Scan TEXT line by line, returning a list of SYMBOL-INFO structs.
   Tracks automaton-block depth so user bindings can be distinguished
   from declarations inside an automaton."
  (let ((results '())
        (in-automaton 0)
        (line-no 0))
    (with-input-from-string (s text)
      (loop for raw = (read-line s nil nil)
            while raw
            do (incf line-no)
               (let ((line (trim raw)))
                 (cond
                   ;; automaton NAME
                   ((cl-ppcre:register-groups-bind (name)
                        ("^automaton\\s+(\\w+)" line)
                      (push (make-symbol-info :name name :kind :automaton :line line-no)
                            results)
                      (incf in-automaton)
                      t))
                   ;; end (only counts when matching an open automaton)
                   ((cl-ppcre:scan "^end\\b" line)
                    (when (plusp in-automaton)
                      (decf in-automaton)))
                   ;; Inside an automaton block: capture loc / contr_var / synclabs
                   ((plusp in-automaton)
                    (cond
                      ((cl-ppcre:register-groups-bind (name)
                           ("^loc\\s+(\\w+)\\s*:" line)
                         (push (make-symbol-info :name name :kind :location :line line-no)
                               results)
                         t))
                      ((cl-ppcre:register-groups-bind (vars)
                           ("^contr_var\\s*:\\s*([^;]+);" line)
                         (dolist (v (split-and-trim vars #\,))
                           (push (make-symbol-info :name v :kind :var :line line-no) results))
                         t))
                      ((cl-ppcre:register-groups-bind (labels)
                           ("^synclabs\\s*:\\s*([^;]+);" line)
                         (dolist (l (split-and-trim labels #\,))
                           (push (make-symbol-info :name l :kind :sync :line line-no) results))
                         t))))
                   ;; Top-level user binding: NAME := RHS;  or  NAME = RHS;
                   ((cl-ppcre:register-groups-bind (name op rhs)
                        ("^(\\w+)\\s*(:=|=)\\s*(.+)$" line)
                      (declare (ignore op))
                      (let ((kind (infer-binding-kind rhs)))
                        ;; If := used, force :scalar regardless of RHS shape.
                        (when (search ":=" line)
                          (setf kind :scalar))
                        (push (make-symbol-info :name name :kind kind :line line-no)
                              results))
                      t))))))
    (nreverse results)))
