;;;; src/syntax.lisp — syntax table + tm-language patterns for .pha files.
;;;; Pattern reference: lem/extensions/dot-mode/dot-mode.lisp.

(defpackage #:phaverlite-mode/syntax
  (:use #:cl #:lem #:lem/language-mode-tools)
  (:export #:*phaverlite-syntax-table*
           #:syntax-keyword-block-attribute))
(in-package #:phaverlite-mode/syntax)

;; Custom face for the structural keywords (automaton, end, loc) so they pop
;; visually. Distinct from the stock attributes lem ships:
;;   syntax-keyword-attribute    -> cyan1   / purple        (other PHAVer keywords)
;;   syntax-constant-attribute   -> LightSteelBlue / #ff00ff (numbers)
;;   syntax-comment-attribute    -> grey-ish               (// /* */)
;; Lem expects literal color names or hex strings, NOT base16 tokens like
;; :base09 (which silently fall back to the default foreground).
(define-attribute syntax-keyword-block-attribute
  (:dark  :foreground "LightGoldenrod" :bold t)
  (:light :foreground "DarkGoldenrod"  :bold t))

(defparameter *block-keywords*
  '("automaton" "end" "loc"))

(defparameter *keywords*
  '("contr_var" "synclabs" "initially"
    "while" "wait" "when" "sync" "do" "goto"))

(defun word-tokens (strings)
  "Build a tm-language alternation regex matching any of STRINGS at word
   boundaries. Longest-first so 'automaton' wins over a hypothetical 'auto'."
  `(:sequence
    :word-boundary
    (:alternation ,@(sort (copy-list strings) #'> :key #'length))
    :word-boundary))

(defun make-tmlanguage-phaverlite ()
  (let ((patterns
         (make-tm-patterns
          (make-tm-line-comment-region "//")
          (make-tm-block-comment-region "/*" "*/")
          (make-tm-match "-?(\\.[0-9]+)|([0-9]+(\\.[0-9]*)?)"
                         :name 'syntax-constant-attribute)
          (make-tm-match (word-tokens *block-keywords*)
                         :name 'syntax-keyword-block-attribute)
          (make-tm-match (word-tokens *keywords*)
                         :name 'syntax-keyword-attribute))))
    (make-tmlanguage :patterns patterns)))

(defparameter *phaverlite-syntax-table*
  (let ((table (make-syntax-table
                :space-chars '(#\space #\tab #\newline)
                :line-comment-string "//"
                :block-comment-pairs '(("/*" . "*/"))))
        (tm (make-tmlanguage-phaverlite)))
    (set-syntax-parser table tm)
    table))
