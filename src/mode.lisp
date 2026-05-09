;;;; src/mode.lisp — top-level: define-major-mode + define-file-type.

(defpackage #:phaverlite-mode
  (:use #:cl #:lem #:lem/language-mode
        #:phaverlite-mode/syntax
        #:phaverlite-mode/indent
        #:phaverlite-mode/commands)
  (:export #:phaverlite-mode
           #:phaverlite-run-buffer))
(in-package #:phaverlite-mode)
