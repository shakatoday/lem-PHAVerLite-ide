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

;;; --- constants -----------------------------------------------------------

(defparameter +plot-filename+ "plot.png")
(defparameter +reach-filename+ "out_reach")
(defparameter +inv-filename+   "out_inv")

;;; --- primitive: render a directory of phaverlite output -----------------

(defun render-plot-dir (dir)
  "Render DIR's out_reach + out_inv to DIR/plot.png via graph(1), then
   open the PNG in the system viewer (`open` on macOS). Returns the
   plot.png pathname on success, NIL on any failure — failures surface
   via lem:message (which is also recorded in lem's *Messages* buffer)."
  (let* ((dir (uiop:ensure-directory-pathname dir))
         (reach (merge-pathnames +reach-filename+ dir))
         (inv   (merge-pathnames +inv-filename+ dir))
         (plot  (merge-pathnames +plot-filename+ dir)))
    (cond
      ((not (probe-file reach))
       (lem:message "Plot: no ~a in ~a (did your .pha use .print?)"
                    +reach-filename+ dir)
       nil)
      ((not (probe-file inv))
       (lem:message "Plot: no ~a in ~a (did your .pha use .print?)"
                    +inv-filename+ dir)
       nil)
      (t
       (handler-case
           (progn
             ;; graph -T png -C -B -q 0.1 <inv> -C -q 0.5 <reach> > <plot>
             (with-open-file (out plot :direction :output
                                       :if-exists :supersede
                                       :element-type '(unsigned-byte 8))
               (uiop:run-program
                (list "graph" "-T" "png" "-C" "-B"
                      "-q" "0.1" (namestring inv)
                      "-C"
                      "-q" "0.5" (namestring reach))
                :output out
                :error-output :string))
             (handler-case
                 (uiop:launch-program (list "open" (namestring plot)))
               (error (e)
                 (lem:message "open failed: ~a; plot at ~a" e plot)))
             (lem:message "Plot: ~a" plot)
             plot)
         (error (e)
           (lem:message "graph failed: ~a" e)
           nil))))))
