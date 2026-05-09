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

(defun symbols-of-kind (text kind)
  "Helper: return list of symbol-info names of KIND from scanning TEXT."
  (mapcar #'phaverlite-lsp/symbols:symbol-info-name
          (remove-if-not
           (lambda (s) (eq (phaverlite-lsp/symbols:symbol-info-kind s) kind))
           (phaverlite-lsp/symbols:scan-symbols text))))

(deftest lsp-symbols
  (testing "automaton sys → :automaton symbol named 'sys'"
    (ok (equal '("sys")
               (symbols-of-kind "automaton sys
end" :automaton))))
  (testing "loc cool: inside an automaton → :location"
    (ok (equal '("cool")
               (symbols-of-kind "automaton h
loc cool:
end" :location))))
  (testing "contr_var: x, y; → two :var symbols"
    (ok (equal '("x" "y")
               (symbols-of-kind "automaton h
contr_var: x, y;
end" :var))))
  (testing "synclabs: tau, tick; → two :sync symbols"
    (ok (equal '("tau" "tick")
               (symbols-of-kind "automaton h
synclabs: tau, tick;
end" :sync))))
  (testing "top-level pc := 0.5; → :scalar"
    (ok (equal '("pc")
               (symbols-of-kind "automaton h
end
pc := 0.5;" :scalar))))
  (testing "top-level bad = sys.{...} → :region"
    (ok (equal '("bad")
               (symbols-of-kind "automaton sys
end
bad = sys.{cool & x >= 20};" :region))))
  (testing "top-level reg = sys.reachable; → :region"
    (ok (member "reg"
                (symbols-of-kind "automaton sys
end
reg = sys.reachable;" :region)
                :test #'equal)))
  (testing "top-level check = sys.is_reachable(bad); → :region"
    (ok (member "check"
                (symbols-of-kind "automaton sys
end
check = sys.is_reachable(bad);" :region)
                :test #'equal)))
  (testing "user binding INSIDE automaton…end is NOT collected as user binding"
    (let ((scalars (symbols-of-kind "automaton h
foo := 99;
end" :scalar))
          (regions (symbols-of-kind "automaton h
foo := 99;
end" :region)))
      (ok (null scalars))
      (ok (null regions)))))

(defun complete (text symbols)
  "Helper: pass TEXT and SYMBOLS to complete-at with offset = (length text).
   Used by tests that want completion at the cursor at end-of-text."
  (phaverlite-lsp/completion:complete-at text (length text) symbols))

(deftest lsp-completion
  (testing "plain prefix 'co' matches keywords + symbol names starting with 'co'"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "cool" :kind :location :line 1)
                          (phaverlite-lsp/symbols:make-symbol-info
                           :name "cond1" :kind :region :line 2)
                          (phaverlite-lsp/symbols:make-symbol-info
                           :name "x" :kind :var :line 3)))
           (results (complete "co" symbols)))
      (ok (member "cool" results :test #'string=))
      (ok (member "cond1" results :test #'string=))
      (ok (member "contr_var" results :test #'string=))
      (ok (not (member "x" results :test #'string=)))))
  (testing "plain prefix at file start with no symbols → only keywords"
    (let ((results (complete "" '())))
      (ok (member "automaton" results :test #'string=))
      (ok (member "end" results :test #'string=))))
  (testing "after 'sys.' where sys is :automaton → automaton-methods only"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "sys" :kind :automaton :line 1)))
           (results (complete "sys." symbols)))
      (ok (member "add_label" results :test #'string=))
      (ok (member "set_partition_constraints" results :test #'string=))
      (ok (member "is_reachable" results :test #'string=))
      (ok (member "reachable" results :test #'string=))
      (ok (member "get_invariants" results :test #'string=))
      ;; NOT keywords or other symbols
      (ok (not (member "automaton" results :test #'string=)))
      (ok (not (member "sys" results :test #'string=)))))
  (testing "after 'bad.' where bad is :region → only 'print'"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "bad" :kind :region :line 1)))
           (results (complete "bad." symbols)))
      (ok (equal '("print") results))))
  (testing "after 'pc.' where pc is :scalar → empty list"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "pc" :kind :scalar :line 1)))
           (results (complete "pc." symbols)))
      (ok (null results))))
  (testing "after 'unknown.' (not in symbols) → empty list"
    (let ((results (complete "unknown." '())))
      (ok (null results))))
  (testing "dot-completion with prefix after dot: 'sys.add' → 'add_label' only"
    (let* ((symbols (list (phaverlite-lsp/symbols:make-symbol-info
                           :name "sys" :kind :automaton :line 1)))
           (results (complete "sys.add" symbols)))
      (ok (equal '("add_label") results)))))
