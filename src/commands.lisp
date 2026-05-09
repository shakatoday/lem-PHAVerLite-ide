;;;; src/commands.lisp — phaverlite-run-buffer command + mode keymap.

(defpackage #:phaverlite-mode/commands
  (:use #:cl #:lem)
  (:export #:phaverlite-run-buffer
           #:*phaverlite-mode-keymap*))
(in-package #:phaverlite-mode/commands)
