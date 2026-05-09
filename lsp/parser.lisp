;;;; lsp/parser.lisp — structural parser for diagnostics.

(defpackage #:phaverlite-lsp/parser
  (:use #:cl)
  (:export #:parse-document
           #:diagnostic
           #:make-diagnostic
           #:diagnostic-start-line
           #:diagnostic-start-col
           #:diagnostic-end-line
           #:diagnostic-end-col
           #:diagnostic-severity
           #:diagnostic-message))
(in-package #:phaverlite-lsp/parser)
