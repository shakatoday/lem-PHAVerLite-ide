;;;; lsp/main.lisp — script entry point.

(defpackage #:phaverlite-lsp/main
  (:use #:cl)
  (:export #:run))
(in-package #:phaverlite-lsp/main)

(defun run ()
  (phaverlite-lsp/server:run-server))
