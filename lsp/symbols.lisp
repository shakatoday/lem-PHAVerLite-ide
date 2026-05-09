;;;; lsp/symbols.lisp — regex-based symbol scanner.

(defpackage #:phaverlite-lsp/symbols
  (:use #:cl)
  (:export #:scan-symbols
           #:symbol-info
           #:make-symbol-info
           #:symbol-info-name
           #:symbol-info-kind
           #:symbol-info-line))
(in-package #:phaverlite-lsp/symbols)
