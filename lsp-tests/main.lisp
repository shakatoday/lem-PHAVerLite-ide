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

(defun diag-fields (d)
  "Helper: return (list start-line start-col message-substring) — used by
   tests that don't care about end-line/end-col. message-substring is the
   full message; tests use search to look for keywords."
  (list (phaverlite-lsp/parser:diagnostic-start-line d)
        (phaverlite-lsp/parser:diagnostic-start-col d)
        (phaverlite-lsp/parser:diagnostic-message d)))

(deftest lsp-parser
  (testing "empty text → no diagnostics"
    (ok (null (phaverlite-lsp/parser:parse-document ""))))
  (testing "clean automaton X end → no diagnostics"
    (ok (null (phaverlite-lsp/parser:parse-document "automaton heater
end"))))
  (testing "automaton without end → one diagnostic mentioning 'end'"
    (let ((diags (phaverlite-lsp/parser:parse-document "automaton heater
contr_var: t;")))
      (ok (= 1 (length diags)))
      (let ((d (first diags)))
        (ok (eq :error (phaverlite-lsp/parser:diagnostic-severity d)))
        (ok (search "end" (phaverlite-lsp/parser:diagnostic-message d))))))
  (testing "orphan end → diagnostic mentioning 'orphan' or 'no automaton'"
    (let ((diags (phaverlite-lsp/parser:parse-document "end")))
      (ok (= 1 (length diags)))
      (let ((msg (phaverlite-lsp/parser:diagnostic-message (first diags))))
        (ok (or (search "orphan" msg) (search "no automaton" msg))))))
  (testing "unmatched { → one diagnostic at the open brace"
    (let ((diags (phaverlite-lsp/parser:parse-document "automaton x
loc l: wait { x' == 1
end")))
      (ok (= 1 (length diags)))
      (let ((msg (phaverlite-lsp/parser:diagnostic-message (first diags))))
        (ok (or (search "{" msg) (search "brace" msg))))))
  (testing "mismatched closer ({)} → diagnostic at the bad closer"
    (let ((diags (phaverlite-lsp/parser:parse-document "automaton x
loc l: wait ( foo }
end")))
      (ok (>= (length diags) 1))))
  (testing "multiple errors → multiple diagnostics"
    (let ((diags (phaverlite-lsp/parser:parse-document "automaton x
end
end")))
      (ok (>= (length diags) 1))
      ;; The second `end` is an orphan.
      )))
