;;;; phaverlite-mode-tests.asd — rove test system for phaverlite-mode.
;;;; Run via: (asdf:test-system :phaverlite-mode-tests)
;;;;     or:  bin/test-mode

(defsystem "phaverlite-mode-tests"
  :description "Rove tests for phaverlite-mode."
  :depends-on ("phaverlite-mode" "rove")
  :pathname "tests"
  :components ((:file "main"))
  :perform (test-op (op c) (symbol-call :rove '#:run c)))
