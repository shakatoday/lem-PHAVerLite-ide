;;;; lsp-tests/main.lisp — rove suite for phaverlite-lsp.

(defpackage #:phaverlite-lsp/tests
  (:use #:cl #:rove))
(in-package #:phaverlite-lsp/tests)

(deftest scaffolding-loads
  (testing "all phaverlite-lsp sub-packages exist"
    (ok (find-package :phaverlite-lsp/parser))
    (ok (find-package :phaverlite-lsp/symbols))
    (ok (find-package :phaverlite-lsp/completion))
    (ok (find-package :phaverlite-lsp/server))
    (ok (find-package :phaverlite-lsp/main))))
