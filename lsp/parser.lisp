;;;; lsp/parser.lisp — structural parser for .pha diagnostics.
;;;;
;;;; Strategy: line-by-line scan. Maintain two stacks:
;;;;   - bracket-stack: each entry is (kind line col), kind ∈ {:paren :brace :bracket}
;;;;   - automaton-stack: each entry is (line col) for an open `automaton`
;;;; On bracket close: pop, check matching kind. Mismatch or empty stack → diag.
;;;; On `end` keyword at start of trimmed line: pop automaton-stack. Empty → orphan.
;;;; At EOF: any remaining stack entries are unmatched-open diagnostics.

(defpackage #:phaverlite-lsp/parser
  (:use #:cl)
  (:export #:parse-document
           #:diagnostic
           #:make-diagnostic
           #:diagnostic-start-line
           #:diagnostic-start-col
           #:diagnostic-end-line
           #:diagnostic-end-col
           #:diagnostic-severity
           #:diagnostic-message))
(in-package #:phaverlite-lsp/parser)

(defstruct diagnostic
  start-line start-col end-line end-col
  severity              ; :error | :warning
  message)

(defun bracket-kind (ch)
  "Return :paren / :brace / :bracket for an opener or closer; NIL otherwise."
  (case ch
    ((#\( #\)) :paren)
    ((#\{ #\}) :brace)
    ((#\[ #\]) :bracket)))

(defun bracket-opener-p (ch) (member ch '(#\( #\{ #\[)))
(defun bracket-closer-p (ch) (member ch '(#\) #\} #\])))

(defun line-start-token (line)
  "Return the first non-whitespace word of LINE (lowercased), or \"\" if blank."
  (let* ((trimmed (string-trim '(#\space #\tab) line))
         (sp (or (position-if (lambda (c) (or (char= c #\space) (char= c #\tab) (char= c #\:)))
                              trimmed)
                 (length trimmed))))
    (string-downcase (subseq trimmed 0 sp))))

(defun parse-document (text)
  "Return list of DIAGNOSTIC structs for TEXT. Empty list = clean."
  (let ((diags '())
        (bracket-stack '())
        (automaton-stack '())
        (line-no 0))
    (with-input-from-string (s text)
      (loop for line = (read-line s nil nil)
            while line
            do (incf line-no)
               (let ((token (line-start-token line)))
                 (cond
                   ((string= token "automaton")
                    (push (list line-no 1) automaton-stack))
                   ((string= token "end")
                    (if automaton-stack
                        (pop automaton-stack)
                        (push (make-diagnostic
                               :start-line line-no :start-col 1
                               :end-line line-no
                               :end-col (length line)
                               :severity :error
                               :message "orphan `end` (no preceding `automaton`)")
                              diags)))))
               (loop for col from 0 below (length line)
                     for ch = (char line col)
                     when (bracket-opener-p ch)
                       do (push (list (bracket-kind ch) line-no (1+ col)) bracket-stack)
                     when (bracket-closer-p ch)
                       do (cond
                            ((null bracket-stack)
                             (push (make-diagnostic
                                    :start-line line-no :start-col (1+ col)
                                    :end-line line-no :end-col (1+ col)
                                    :severity :error
                                    :message (format nil "unmatched closing `~c`" ch))
                                   diags))
                            ((not (eq (first (first bracket-stack)) (bracket-kind ch)))
                             (let ((opener (pop bracket-stack)))
                               (declare (ignore opener))
                               (push (make-diagnostic
                                      :start-line line-no :start-col (1+ col)
                                      :end-line line-no :end-col (1+ col)
                                      :severity :error
                                      :message (format nil "mismatched closing `~c`" ch))
                                     diags)))
                            (t (pop bracket-stack)))))
      ;; EOF: any remaining open brackets are unmatched.
      (dolist (entry bracket-stack)
        (destructuring-bind (kind ln col) entry
          (push (make-diagnostic
                 :start-line ln :start-col col :end-line ln :end-col col
                 :severity :error
                 :message (format nil "unmatched opening `~a` (no closer)"
                                  (case kind (:paren "(") (:brace "{") (:bracket "["))))
                diags)))
      ;; EOF: any remaining open automatons are unclosed.
      (dolist (entry automaton-stack)
        (destructuring-bind (ln col) entry
          (push (make-diagnostic
                 :start-line ln :start-col col :end-line ln :end-col col
                 :severity :error
                 :message "`automaton` without matching `end`")
                diags))))
    (nreverse diags)))

