;;;; phaverlite-lsp-tests.asd — rove test system for phaverlite-lsp.
;;;; Run via: bin/test-mode (which now invokes BOTH suites in
;;;; separate sbcls), or directly via:
;;;;   (asdf:test-system :phaverlite-lsp-tests)

(defsystem "phaverlite-lsp-tests"
  :description "Rove tests for phaverlite-lsp (server-side)."
  :depends-on ("phaverlite-lsp" "rove")
  :pathname "lsp-tests"
  :components ((:file "main"))
  :perform (test-op (op c) (symbol-call :rove '#:run c)))
