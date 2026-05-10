;;;; phaverlite-mode-lsp.asd — client-side glue inside lem.
;;;; Registers the phaverlite LSP server with lem-lsp-mode for
;;;; phaverlite-mode buffers.

(defsystem "phaverlite-mode-lsp"
  :description "lem-lsp-mode glue for phaverlite-mode."
  :depends-on ("phaverlite-mode" "lem-lsp-mode" "alexandria")
  :pathname "src-lsp"
  :serial t
  :components ((:file "spec")
               (:file "debug-trace")))
