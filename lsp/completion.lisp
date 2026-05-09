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
