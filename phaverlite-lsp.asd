;;;; phaverlite-lsp.asd — minimal LSP server for .pha files.
;;;; Standalone system (no lem deps) — server is spawned by
;;;; lem-lsp-mode as a separate process via bin/phaverlite-lsp.
;;;; See docs/superpowers/specs/2026-05-09-sub-project-e-design.md.

(defsystem "phaverlite-lsp"
  :description "LSP server for the PHAVer (.pha) language."
  :depends-on ("jsonrpc"
               "jsonrpc/transport/stdio"
               "cl-ppcre"
               "babel")
  :pathname "lsp"
  :serial t
  :components ((:file "symbols")
               (:file "completion")
               (:file "server")
               (:file "main")))
