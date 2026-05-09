;;;; phaverlite-mode.asd — main system for the .pha major mode.
;;;; Loaded by config/init.lisp via (ql:quickload :phaverlite-mode).
;;;; Layout follows lem's convention: asd at repo root, :pathname "src".

(defsystem "phaverlite-mode"
  :description "PHAVer (.pha) major mode for lem."
  :depends-on ("lem/core")
  :pathname "src"
  :serial t
  :components ((:file "syntax")
               (:file "indent")
               (:file "commands")
               (:file "mode")))
