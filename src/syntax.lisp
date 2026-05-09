;;;; src/syntax.lisp — syntax table + tm-language patterns for .pha files.

(defpackage #:phaverlite-mode/syntax
  (:use #:cl #:lem)
  (:export #:*phaverlite-syntax-table*
           #:syntax-keyword-block-attribute))
(in-package #:phaverlite-mode/syntax)
