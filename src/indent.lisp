;;;; src/indent.lisp — block-aware indent calculator for .pha files.
;;;;
;;;; Total function: calc-indent always returns a non-negative integer.
;;;; Algorithm:
;;;;   1. Walk back to the previous non-blank line.
;;;;   2. base = leading-whitespace column of that line.
;;;;   3. If that line ends in ':' or matches "^automaton\b" → base + 4.
;;;;   4. Else if current line's first non-whitespace token is "end"
;;;;      → max(base - 4, 0).
;;;;   5. Else → base.

(defpackage #:phaverlite-mode/indent
  (:use #:cl #:lem)
  (:export #:calc-indent))
(in-package #:phaverlite-mode/indent)

(defparameter +indent-step+ 4)

(defun line-text (point)
  "Return the text of the line POINT is on, without trailing newline."
  (let ((start (lem:copy-point point :temporary))
        (end (lem:copy-point point :temporary)))
    (lem:line-start start)
    (lem:line-end end)
    (lem:points-to-string start end)))

(defun leading-whitespace-cols (line)
  "Number of leading space chars in LINE. Tabs count as 1; we only ever
   produce spaces ourselves, and the corpus uses spaces."
  (or (position-if-not (lambda (c) (or (eql c #\space) (eql c #\tab))) line)
      0))

(defun trim-line (line)
  (string-trim '(#\space #\tab) line))

(defun line-ends-with-colon-p (line)
  (let ((s (trim-line line)))
    (and (plusp (length s))
         (char= (char s (1- (length s))) #\:))))

(defun line-starts-with-automaton-p (line)
  (let ((s (trim-line line)))
    (and (>= (length s) (length "automaton"))
         (string= s "automaton" :end1 (length "automaton"))
         (or (= (length s) (length "automaton"))
             (let ((c (char s (length "automaton"))))
               (or (char= c #\space) (char= c #\tab)))))))

(defun line-starts-with-end-p (line)
  (let ((s (trim-line line)))
    (and (>= (length s) 3)
         (string= s "end" :end1 3)
         (or (= (length s) 3)
             (let ((c (char s 3)))
               (not (alpha-char-p c)))))))

(defun blank-text-p (line)
  (zerop (length (trim-line line))))

(defun previous-non-blank-line-text (point)
  "Walk back from POINT. Return (values TEXT FOUND-P). If the cursor is
   already on the first line, FOUND-P is NIL."
  (let ((p (lem:copy-point point :temporary)))
    (loop
      (unless (lem:line-offset p -1)
        (return (values "" nil)))
      (let ((text (line-text p)))
        (unless (blank-text-p text)
          (return (values text t)))))))

(defun calc-indent (point)
  "Return the column (integer ≥ 0) the line containing POINT should
   start at. Total function — never errors."
  (let* ((current-line (line-text point)))
    (multiple-value-bind (prev found-p)
        (previous-non-blank-line-text point)
      (if (not found-p)
          0
          (let* ((base (leading-whitespace-cols prev)))
            (cond
              ((line-starts-with-end-p current-line)
               (max 0 (- base +indent-step+)))
              ((line-ends-with-colon-p prev)
               (+ base +indent-step+))
              ((line-starts-with-automaton-p prev)
               (+ base +indent-step+))
              (t base)))))))
