;;;; lsp/server.lisp — JSON-RPC handlers + run-server.

(defpackage #:phaverlite-lsp/server
  (:use #:cl)
  (:import-from #:phaverlite-lsp/parser
                #:parse-document
                #:diagnostic-start-line
                #:diagnostic-start-col
                #:diagnostic-end-line
                #:diagnostic-end-col
                #:diagnostic-severity
                #:diagnostic-message)
  (:import-from #:phaverlite-lsp/symbols
                #:scan-symbols)
  (:import-from #:phaverlite-lsp/completion
                #:complete-at)
  (:export #:run-server))
(in-package #:phaverlite-lsp/server)

;;; --- diagnostic log file (independent of stdout/stderr to avoid races) -

(defvar *log-stream* nil
  "Open file stream for diagnostic logging. Opened in run-server.")

;;; --- document store ----------------------------------------------------

(defvar *documents* (make-hash-table :test 'equal)
  "uri → DOCUMENT struct.")

(defstruct document
  uri text version
  symbols)              ; cached output of scan-symbols

;;; --- helpers -----------------------------------------------------------

(defun get-field (params key)
  "Look up KEY (string) in a hash-table or alist or plist PARAMS.
   jsonrpc / yason returns hash-tables by default; defensive fallbacks."
  (cond
    ((hash-table-p params) (gethash key params))
    ((and (consp params) (consp (car params)))
     (cdr (assoc key params :test #'equal)))
    (t nil)))

(defun ht (&rest pairs)
  "Build a string-keyed hash-table (yason → JSON object). PAIRS are
   alternating KEY VALUE."
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k h) v))
    h))

(defun line-character-to-offset (text line character)
  "LSP positions are 0-based (line, character). Convert to a byte offset
   in TEXT. Clamp to [0, length)."
  (let ((offset 0)
        (current-line 0)
        (len (length text)))
    (loop while (and (< offset len) (< current-line line))
          do (when (char= (char text offset) #\newline)
               (incf current-line))
             (incf offset))
    (let ((line-end (or (position #\newline text :start offset) len)))
      (min (+ offset character) line-end len))))

(defun severity->lsp (sev)
  "LSP severity: 1=error, 2=warning, 3=info, 4=hint."
  (case sev (:error 1) (:warning 2) (otherwise 3)))

(defun diagnostic->lsp (d)
  "Convert our DIAGNOSTIC struct → LSP Diagnostic hash-table (yason → JSON object)."
  (ht "range" (ht "start" (ht "line" (1- (diagnostic-start-line d))
                              "character" (1- (diagnostic-start-col d)))
                  "end"   (ht "line" (1- (diagnostic-end-line d))
                              "character" (1- (diagnostic-end-col d))))
      "severity" (severity->lsp (diagnostic-severity d))
      "message"  (diagnostic-message d)
      "source"   "phaverlite-lsp"))

(defun publish-diagnostics (server uri diags)
  (format *log-stream* "publish-diagnostics: uri=~a diag-count=~a~%" uri (length diags))
  (force-output *log-stream*)
  (handler-case
      (progn
        ;; CRITICAL: encode as a VECTOR so yason emits a JSON array `[]`
        ;; even when empty. yason encodes the empty list `()` as JSON
        ;; `null`, which lem-lsp-mode's typed Diagnostic[] parser rejects
        ;; — silently breaking the workspace's diagnostic display.
        (jsonrpc:notify server "textDocument/publishDiagnostics"
                        (ht "uri" uri
                            "diagnostics"
                            (coerce (mapcar #'diagnostic->lsp diags) 'vector)))
        (format *log-stream* "publish-diagnostics: notify returned~%")
        (force-output *log-stream*))
    (error (e)
      (format *log-stream* "publish-diagnostics ERROR: ~a~%" e)
      (force-output *log-stream*))))

(defun reparse-and-publish (server uri text)
  (format *log-stream* "reparse-and-publish: text-len=~a~%" (length text))
  (force-output *log-stream*)
  (let ((diags (handler-case (parse-document text)
                 (error (e)
                   (format *log-stream* "parser error: ~a~%" e)
                   (force-output *log-stream*)
                   '()))))
    (publish-diagnostics server uri diags)))

;;; --- handlers ----------------------------------------------------------
;;; Every handler returns a hash-table (encoded as a JSON object) or NIL.
;;; LSP "no result" notifications return NIL. Errors are caught at the
;;; top level (run-server's handler-bind), never reach the SBCL debugger.

(defun handle-initialize (server params)
  (declare (ignore server params))
  (format *log-stream* "handle-initialize~%") (force-output *log-stream*)
  ;; Minimal capabilities — only textDocumentSync, no completionProvider.
  ;; Diagnostics don't need a capability declaration; they're a server→client
  ;; notification (textDocument/publishDiagnostics) the server can send any
  ;; time. completionProvider may have triggered a typed-parser error in
  ;; lem-lsp-mode that silently broke the post-initialize callback chain,
  ;; preventing textDocument/didOpen from firing.
  (ht "capabilities"
      (ht "textDocumentSync" 1)))

(defun handle-initialized (server params)
  (declare (ignore server params))
  (format *log-stream* "handle-initialized~%") (force-output *log-stream*)
  nil)

(defun handle-shutdown (server params)
  (declare (ignore server params))
  nil)

(defun handle-exit (server params)
  (declare (ignore server params))
  (uiop:quit 0))

(defun handle-did-open (server params)
  (format *log-stream* "handle-did-open: entered~%") (force-output *log-stream*)
  (format *log-stream* "  params type: ~a~%" (type-of params)) (force-output *log-stream*)
  (when (hash-table-p params)
    (format *log-stream* "  params keys: ~a~%"
            (loop for k being the hash-keys of params collect k))
    (force-output *log-stream*))
  (handler-case
      (let* ((td (get-field params "textDocument"))
             (uri (get-field td "uri"))
             (text (get-field td "text"))
             (version (get-field td "version")))
        (format *log-stream* "handle-did-open: uri=~a text-len=~a~%" uri (length text))
    (force-output *log-stream*)
    (format *log-stream* "handle-did-open: about to call scan-symbols~%")
    (force-output *log-stream*)
    (let ((symbols
           (handler-case (scan-symbols text)
             (error (e)
               (format *log-stream* "scan-symbols ERROR: ~a~%" e)
               (force-output *log-stream*)
               '()))))
      (format *log-stream* "handle-did-open: scan-symbols returned~%")
      (force-output *log-stream*)
      (format *log-stream* "handle-did-open: scanned ~a symbols~%" (length symbols))
      (force-output *log-stream*)
      (handler-case
          (setf (gethash uri *documents*)
                (make-document :uri uri :text text :version version :symbols symbols))
        (error (e)
          (format *log-stream* "make-document/gethash ERROR: ~a~%" e)
          (force-output *log-stream*))))
    (format *log-stream* "handle-did-open: about to reparse-and-publish~%")
    (force-output *log-stream*)
    (handler-case (reparse-and-publish server uri text)
      (error (e)
        (format *log-stream* "reparse-and-publish ERROR: ~a~%" e)
        (force-output *log-stream*)))
    (format *log-stream* "handle-did-open: done~%") (force-output *log-stream*)
    nil)
    (error (e)
      (format *log-stream* "handle-did-open ESCAPED with: ~a~%" e)
      (force-output *log-stream*)
      nil)))

(defun handle-did-change (server params)
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (changes (get-field params "contentChanges"))
         ;; Full sync — last change is the new full text.
         (new-text (get-field (car (last changes)) "text"))
         (doc (gethash uri *documents*)))
    (when doc
      (setf (document-text doc) new-text
            (document-symbols doc) (handler-case (scan-symbols new-text)
                                     (error (e)
                                       (format *log-stream* "scan error: ~a~%" e)
                                       '())))
      (reparse-and-publish server uri new-text))
    nil))

(defun handle-did-save (server params)
  (handle-did-change server params))

(defun handle-did-close (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri")))
    (remhash uri *documents*)
    nil))

(defun handle-completion (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (pos (get-field params "position"))
         (line (get-field pos "line"))
         (character (get-field pos "character"))
         (doc (gethash uri *documents*))
         (items '()))
    (when doc
      (let* ((offset (line-character-to-offset (document-text doc) line character))
             (completions (handler-case
                              (complete-at (document-text doc) offset
                                           (document-symbols doc))
                            (error (e)
                              (format *log-stream* "complete-at error: ~a~%" e)
                              '()))))
        (setf items
              (mapcar (lambda (label)
                        (ht "label" label "kind" 14))   ; 14 = Keyword
                      completions))))
    ;; Omit `isIncomplete` — LSP spec defaults it to false on the client
    ;; side, and avoiding the field sidesteps yason's NIL/false ambiguity.
    (ht "items" items)))

;;; --- entry point -------------------------------------------------------

(defun run-server ()
  "Start the LSP server on stdio. Blocks on the reading loop until
   the exit handler calls (uiop:quit 0)."
  ;; CRITICAL: disable SBCL's interactive debugger. If a handler raises
  ;; an uncaught condition, the debugger prompt would write to stdout
  ;; (the LSP transport), corrupting the JSON-RPC stream and causing
  ;; the lem client to hang waiting for a valid response.
  #+sbcl (sb-ext:disable-debugger)
  ;; Open a dedicated log file (not *error-output*, which has thread races).
  (ensure-directories-exist "var/log/")
  (setf *log-stream*
        (open "var/log/lsp-trace.log"
              :direction :output
              :if-exists :supersede
              :if-does-not-exist :create))
  (let ((server (jsonrpc:make-server)))
    (jsonrpc:expose server "initialize"          (lambda (p) (handle-initialize server p)))
    (jsonrpc:expose server "initialized"         (lambda (p) (handle-initialized server p)))
    (jsonrpc:expose server "shutdown"            (lambda (p) (handle-shutdown server p)))
    (jsonrpc:expose server "exit"                (lambda (p) (handle-exit server p)))
    (jsonrpc:expose server "textDocument/didOpen"  (lambda (p) (handle-did-open server p)))
    (jsonrpc:expose server "textDocument/didChange" (lambda (p) (handle-did-change server p)))
    (jsonrpc:expose server "textDocument/didSave"  (lambda (p) (handle-did-save server p)))
    (jsonrpc:expose server "textDocument/didClose" (lambda (p) (handle-did-close server p)))
    (jsonrpc:expose server "textDocument/completion" (lambda (p) (handle-completion server p)))
    ;; server-listen runs the reading loop in THIS thread (per stdio
    ;; transport's start-server impl), spawning a separate processing
    ;; thread. It blocks until stdin EOF; no extra (loop (sleep 1)) needed.
    (jsonrpc:server-listen server :mode :stdio)))
