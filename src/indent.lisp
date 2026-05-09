;;;; src/indent.lisp — block-aware indent calculator for .pha files.

(defpackage #:phaverlite-mode/indent
  (:use #:cl #:lem)
  (:export #:calc-indent))
(in-package #:phaverlite-mode/indent)
