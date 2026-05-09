;;;; tests/main.lisp — rove suite for phaverlite-mode.

(defpackage #:phaverlite-mode/tests
  (:use #:cl #:rove))
(in-package #:phaverlite-mode/tests)

(deftest scaffolding-loads
  (testing "phaverlite-mode package exists after loading the test system"
    (ok (find-package :phaverlite-mode)))
  (testing "all sub-packages exist"
    (ok (find-package :phaverlite-mode/syntax))
    (ok (find-package :phaverlite-mode/indent))
    (ok (find-package :phaverlite-mode/commands))))
