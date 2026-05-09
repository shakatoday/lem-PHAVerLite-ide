;;;; src/indent.lisp — block-aware indent calculator for .pha files.
;;;;
;;;; Total function: calc-indent always returns a non-negative integer.
;;;;
;;;; PHAVer's blocks:
;;;;   automaton X        ... end           — explicit close
;;;;   loc NAME:          ... (no close)    — implicit close at next loc /
;;;;                                         initially / contr_var / synclabs / end
;;;;
;;;; Algorithm: walk back from POINT through previous lines, looking for the
;;;; nearest "structural anchor" (an automaton/loc/end keyword line). The
;;;; anchor + the current line's first token determine the indent column.
;;;;
;;;;   current line starts with…   ⇒  result
;;;;   automaton                       0  (top level)
;;;;   end                             column-of-enclosing-automaton
;;;;   loc/initially/contr_var/synclabs (section keyword)
;;;;                                   column-of-enclosing-automaton + 4
;;;;   anything else (statement)       column-of-enclosing-loc-or-automaton + 4
;;;;
;;;; If no enclosing anchor is found (we're at the top of the file or only
;;;; saw `end` lines while walking back), return 0.
;;;;
;;;; The walk stops at the first matching anchor — `end` is treated as a
;;;; "no enclosing block" signal because it closes the most recent automaton.

(defpackage #:phaverlite-mode/indent
  (:use #:cl #:lem)
  (:export #:calc-indent))
(in-package #:phaverlite-mode/indent)

(defparameter +indent-step+ 4)

(defparameter *section-keywords*
  '("loc" "initially" "contr_var" "synclabs"))

(defun line-text (point)
  "Return the text of the line POINT is on, without trailing newline."
  (let ((start (lem:copy-point point :temporary))
        (end (lem:copy-point point :temporary)))
    (lem:line-start start)
    (lem:line-end end)
    (lem:points-to-string start end)))

(defun leading-whitespace-cols (line)
  "Number of leading space chars in LINE (tabs count as 1; the corpus
   uses spaces, and our own output is always spaces)."
  (or (position-if-not (lambda (c) (or (eql c #\space) (eql c #\tab))) line)
      0))

(defun trim-line (line)
  (string-trim '(#\space #\tab) line))

(defun blank-text-p (line)
  (zerop (length (trim-line line))))

(defun first-token (line)
  "Return the first whitespace-delimited token of LINE, or \"\" if blank."
  (let* ((s (trim-line line))
         (end (or (position-if (lambda (c) (member c '(#\space #\tab #\: #\;)))
                               s)
                  (length s))))
    (subseq s 0 end)))

(defun line-starts-with-automaton-p (line)
  (string= (first-token line) "automaton"))

(defun line-starts-with-end-p (line)
  (string= (first-token line) "end"))

(defun line-starts-with-section-p (line)
  (member (first-token line) *section-keywords* :test #'string=))

(defun line-starts-with-loc-p (line)
  (string= (first-token line) "loc"))

(defun walk-back-anchor (point)
  "Walk back through POINT's previous non-blank lines. Return
   (values KIND COLUMN) where KIND is one of :automaton, :loc, :end, :none.
   COLUMN is the leading-whitespace column of the matching line, or 0
   if KIND is :none.

   :automaton — found an `automaton` line first.
   :loc       — found a `loc … :` line first.
   :end       — found an `end` line first (we are past the close of an
                 automaton; treat as no enclosing block).
   :none      — reached the top of the buffer with no anchor."
  (let ((p (lem:copy-point point :temporary)))
    (loop
      (unless (lem:line-offset p -1)
        (return (values :none 0)))
      (let ((text (line-text p)))
        (unless (blank-text-p text)
          (let ((col (leading-whitespace-cols text)))
            (cond
              ((line-starts-with-automaton-p text)
               (return (values :automaton col)))
              ((line-starts-with-end-p text)
               (return (values :end col)))
              ((line-starts-with-loc-p text)
               (return (values :loc col))))))))))

(defun walk-back-enclosing-automaton (point)
  "Walk back past any number of lines (including intervening `loc`s and
   statements) until we find the enclosing `automaton` line. Returns its
   leading-whitespace column, or NIL if none."
  (let ((p (lem:copy-point point :temporary)))
    (loop
      (unless (lem:line-offset p -1)
        (return nil))
      (let ((text (line-text p)))
        (unless (blank-text-p text)
          (cond
            ((line-starts-with-automaton-p text)
             (return (leading-whitespace-cols text)))
            ;; If we hit an `end` first, the most recent automaton already
            ;; closed — there is no enclosing automaton from POINT's view.
            ((line-starts-with-end-p text)
             (return nil))))))))

(defun calc-indent (point)
  "Return the column (integer ≥ 0) the line containing POINT should
   start at. Total function — never errors. See file header for algorithm."
  (let* ((cur (line-text point))
         (cur-token (first-token cur)))
    (cond
      ;; automaton header is always at column 0.
      ((string= cur-token "automaton")
       0)
      ;; `end` closes the enclosing automaton — align with it.
      ((string= cur-token "end")
       (or (walk-back-enclosing-automaton point) 0))
      ;; Section keywords (loc, initially, contr_var, synclabs) hang one
      ;; step inside the enclosing automaton.
      ((line-starts-with-section-p cur)
       (let ((auto-col (walk-back-enclosing-automaton point)))
         (if auto-col (+ auto-col +indent-step+) 0)))
      ;; Statement lines: indent inside the most recent loc body, or
      ;; the enclosing automaton if there is no loc above us.
      (t
       (multiple-value-bind (kind col) (walk-back-anchor point)
         (case kind
           ((:loc :automaton) (+ col +indent-step+))
           ;; :end means we're past a closed automaton — top level.
           (:end 0)
           (:none 0)))))))
