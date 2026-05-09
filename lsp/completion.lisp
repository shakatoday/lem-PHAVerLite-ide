;;;; lsp/completion.lisp — keyword + symbol + kind-aware dot completion.

(defpackage #:phaverlite-lsp/completion
  (:use #:cl)
  (:import-from #:phaverlite-lsp/symbols
                #:symbol-info
                #:symbol-info-name
                #:symbol-info-kind)
  (:export #:complete-at
           #:+keywords+
           #:+automaton-methods+
           #:+region-methods+))
(in-package #:phaverlite-lsp/completion)

(defparameter +keywords+
  '("automaton" "loc" "wait" "when" "sync" "do" "goto" "initially"
    "contr_var" "synclabs" "end"))

(defparameter +automaton-methods+
  '("add_label" "set_partition_constraints" "set_refine_constraints"
    "is_reachable" "reachable" "get_invariants"))

(defparameter +region-methods+ '("print"))

(defun ident-char-p (ch)
  (or (alpha-char-p ch) (digit-char-p ch) (char= ch #\_)))

(defun extract-context (text offset)
  "Look at TEXT just before OFFSET. Return one of:
     (:plain prefix)         — plain identifier prefix
     (:dot receiver prefix)  — after RECEIVER. (PREFIX may be empty)"
  (let ((end (min offset (length text))))
    ;; Walk backwards while ident chars
    (let ((p end))
      (loop while (and (> p 0) (ident-char-p (char text (1- p))))
            do (decf p))
      ;; If the char immediately before p is `.`, look back another ident.
      (cond
        ((and (> p 0) (char= (char text (1- p)) #\.))
         (let ((dot-pos (1- p))
               (q (1- p)))
           (loop while (and (> q 0) (ident-char-p (char text (1- q))))
                 do (decf q))
           (if (= q dot-pos)
               ;; "." with no receiver to the left → treat as plain prefix
               (list :plain (subseq text p end))
               (list :dot
                     (subseq text q dot-pos)
                     (subseq text p end)))))
        (t
         (list :plain (subseq text p end)))))))

(defun has-prefix-p (string prefix)
  "Case-sensitive prefix check."
  (let ((sl (length string)) (pl (length prefix)))
    (and (>= sl pl)
         (string= string prefix :end1 pl))))

(defun complete-at (text offset symbols)
  "Return a list of completion strings for the identifier at OFFSET
   in TEXT, given the SYMBOLS scanned from the document."
  (destructuring-bind (kind &rest rest) (extract-context text offset)
    (case kind
      (:dot
       (destructuring-bind (receiver prefix) rest
         (let ((info (find receiver symbols
                           :key #'symbol-info-name :test #'string=)))
           (let ((methods (case (and info (symbol-info-kind info))
                            (:automaton +automaton-methods+)
                            (:region    +region-methods+)
                            (otherwise  '()))))
             (remove-if-not (lambda (m) (has-prefix-p m prefix)) methods)))))
      (:plain
       (let ((prefix (first rest))
             (candidates (append +keywords+
                                 (mapcar #'symbol-info-name symbols))))
         (remove-if-not (lambda (c) (has-prefix-p c prefix)) candidates))))))
