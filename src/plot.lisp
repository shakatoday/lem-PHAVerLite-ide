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
                    +reach-filename+ (uiop:enough-pathname dir (uiop:getcwd)))
       nil)
      ((not (probe-file inv))
       (lem:message "Plot: no ~a in ~a (did your .pha use .print?)"
                    +inv-filename+ (uiop:enough-pathname dir (uiop:getcwd)))
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
                 ;; Show plot location relative to project root — full
                 ;; absolute paths leak user/project info in screenshots.
                 (lem:message "open failed: ~a; plot at ~a"
                              e (uiop:enough-pathname plot (uiop:getcwd)))))
             (lem:message "Plot: ~a" (uiop:enough-pathname plot (uiop:getcwd)))
             plot)
         (error (e)
           (lem:message "graph failed: ~a" e)
           nil))))))

;;; --- M-x phaverlite-plot-buffer (single-run plot command) ---------------

(defun plot-dir-for-template (template-path)
  "Where standalone-plot output goes for a given .pha source:
   var/plot/<basename>/."
  (let ((basename (pathname-name template-path)))
    (merge-pathnames (format nil "var/plot/~a/" basename)
                     (uiop:getcwd))))

(define-command phaverlite-plot-buffer (&optional buffer) ()
  "Run phaverlite on the current .pha buffer in a per-buffer plot dir,
   then render and open the resulting plot. Refuses if a sweep is in
   progress (use `p` on a sweep row instead). Same buffer-precondition
   pattern as phaverlite-run-buffer (must visit a file; modified-buffer
   y/n prompt)."
  (let* ((buf (or buffer (lem:current-buffer)))
         (path (lem:buffer-filename buf)))
    (cond
      ((null path)
       (lem:message "Buffer not visiting a file"))
      (phaverlite-mode/sweep::*active-sweep*
       (lem:message "Sweep in progress; use 'p' on a sweep row instead"))
      ((and (lem:buffer-modified-p buf)
            (not (lem:prompt-for-y-or-n-p
                  "Buffer modified. Save and run plot?")))
       nil)                                ; silent abort
      (t
       (when (lem:buffer-modified-p buf)
         (lem:save-buffer buf))
       (let ((plot-dir (plot-dir-for-template path)))
         (ensure-directories-exist plot-dir)
         (handler-case
             (let ((proc (uiop:launch-program
                          (list "phaverlite" (namestring path))
                          :input nil :output nil :error-output nil
                          :directory plot-dir)))
               ;; Synchronous wait — single short run, no cancellation
               ;; in the prototype plot path. stdout/stderr discarded;
               ;; what we care about is the side-effect files.
               (uiop:wait-process proc)
               (render-plot-dir plot-dir))
           (error (e)
             (lem:message "phaverlite failed: ~a" e)
             nil)))))))

;;; --- mode keybinding ----------------------------------------------------

(define-key phaverlite-mode/commands:*phaverlite-mode-keymap*
            "C-c C-p" 'phaverlite-plot-buffer)

;;; --- p on a sweep row (per-pc plot command) -----------------------------

(defun parse-sweep-row-pc (line-text)
  "Return the first whitespace-separated token of LINE-TEXT as a string,
   or NIL if the line doesn't look like a sweep result row."
  (let* ((trimmed (string-trim '(#\space #\tab) line-text))
         (sp (or (position-if (lambda (c) (member c '(#\space #\tab)))
                              trimmed)
                 (length trimmed)))
         (token (subseq trimmed 0 sp)))
    (when (and (plusp (length token))
               ;; Must start with a digit or sign — filters out header,
               ;; status, and separator lines.
               (or (digit-char-p (char token 0))
                   (and (member (char token 0) '(#\- #\+))
                        (> (length token) 1)
                        (digit-char-p (char token 1)))))
      token)))

(defun current-line-text (buffer)
  "Return the text of the line containing BUFFER's point."
  (let ((start (lem:copy-point (lem:buffer-point buffer) :temporary))
        (end (lem:copy-point (lem:buffer-point buffer) :temporary)))
    (lem:line-start start)
    (lem:line-end end)
    (lem:points-to-string start end)))

(define-command phaverlite-sweep-plot-row () ()
  "Plot the reach-set for the sweep row at point. Operates on the
   *phaverlite-sweep* buffer; reads the pc value from the current line's
   first token."
  (let ((buf (lem:current-buffer)))
    (cond
      ((not (string= (lem:buffer-name buf) "*phaverlite-sweep*"))
       (lem:message "Not in a *phaverlite-sweep* buffer"))
      (t
       (let* ((line (current-line-text buf))
              (pc-token (parse-sweep-row-pc line))
              (basename (lem:buffer-value
                         buf 'phaverlite-mode/sweep::phaverlite-sweep-template-basename)))
         (cond
           ((null pc-token)
            (lem:message "No sweep row at point"))
           ((null basename)
            (lem:message "No template basename on sweep buffer (run a sweep first)"))
           (t
            (let ((pc-dir (merge-pathnames
                           (format nil "var/sweep/~a/pc-~a/"
                                   basename pc-token)
                           (uiop:getcwd))))
              (cond
                ((not (uiop:directory-exists-p pc-dir))
                 (lem:message
                  "No plot data for pc=~a (was it cancelled?)" pc-token))
                (t
                 (render-plot-dir pc-dir)))))))))))

;; The phaverlite-sweep-results-mode keymap is defined in src/sweep.lisp
;; and exists by the time plot.lisp loads (asd serial order). Bind p
;; here, after phaverlite-sweep-plot-row exists.
(define-key phaverlite-mode/sweep::*phaverlite-sweep-results-mode-keymap*
            "p" 'phaverlite-sweep-plot-row)
