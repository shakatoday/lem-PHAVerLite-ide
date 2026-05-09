;;;; src/plot.lisp — plotutils integration for PHAVerLite reach-set /
;;;; invariant output.
;;;;
;;;; Two interactive surfaces:
;;;;   M-x phaverlite-plot-buffer       (C-c C-p)  — standalone .pha plot
;;;;   M-x phaverlite-sweep-plot-row    (`p` in *phaverlite-sweep*)
;;;; Both share a single primitive: render-plot-dir.
;;;; See docs/superpowers/specs/2026-05-09-sub-project-d-design.md.

(defpackage #:phaverlite-mode/plot
  (:use #:cl #:lem)
  (:export #:phaverlite-plot-buffer
           #:phaverlite-sweep-plot-row))
(in-package #:phaverlite-mode/plot)
