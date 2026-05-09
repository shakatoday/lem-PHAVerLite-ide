;;;; src-lsp/spec.lisp — register the phaverlite LSP server with
;;;; lem-lsp-mode. One define-language-spec form, period.

(defpackage #:phaverlite-mode-lsp
  (:use #:cl))
(in-package #:phaverlite-mode-lsp)

(lem-lsp-mode/lsp-mode:define-language-spec
    (phaverlite-spec phaverlite-mode:phaverlite-mode)
  :language-id "phaverlite"
  :command (list (namestring (merge-pathnames "bin/phaverlite-lsp"
                                              (uiop:getcwd))))
  :connection-mode :stdio)
