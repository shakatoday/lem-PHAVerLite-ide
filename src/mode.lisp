;;;; src/mode.lisp — top-level: define-major-mode + define-file-type binding.
;;;; Pattern reference: lem/extensions/dot-mode/dot-mode.lisp.

(defpackage #:phaverlite-mode
  (:use #:cl #:lem #:lem/language-mode
        #:phaverlite-mode/syntax
        #:phaverlite-mode/indent
        #:phaverlite-mode/commands)
  (:export #:phaverlite-mode
           #:phaverlite-run-buffer
           #:*phaverlite-mode-hook*))
(in-package #:phaverlite-mode)

(define-major-mode phaverlite-mode language-mode
    (:name "PHAVer"
     :keymap *phaverlite-mode-keymap*
     :syntax-table *phaverlite-syntax-table*
     :mode-hook *phaverlite-mode-hook*)
  (setf (variable-value 'enable-syntax-highlight) t
        (variable-value 'tab-width) 4
        (variable-value 'calc-indent-function) 'phaverlite-mode/indent:calc-indent
        (variable-value 'line-comment) "//"
        (variable-value 'beginning-of-defun-function) nil
        (variable-value 'end-of-defun-function) nil))

(define-file-type ("pha") phaverlite-mode)
