;;;; lsp/server.lisp — JSON-RPC lifecycle + handlers.

(defpackage #:phaverlite-lsp/server
  (:use #:cl)
  (:export #:run-server))
(in-package #:phaverlite-lsp/server)
