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
  "Convert our DIAGNOSTIC struct → LSP Diagnostic alist (yason-friendly)."
  `(("range" . (("start" . (("line" . ,(1- (diagnostic-start-line d)))
                            ("character" . ,(1- (diagnostic-start-col d)))))
                ("end"   . (("line" . ,(1- (diagnostic-end-line d)))
                            ("character" . ,(1- (diagnostic-end-col d)))))))
    ("severity" . ,(severity->lsp (diagnostic-severity d)))
    ("message"  . ,(diagnostic-message d))
    ("source"   . "phaverlite-lsp")))

(defun publish-diagnostics (server uri diags)
  (jsonrpc:notify server "textDocument/publishDiagnostics"
                  `(("uri" . ,uri)
                    ("diagnostics" . ,(mapcar #'diagnostic->lsp diags)))))

(defun reparse-and-publish (server uri text)
  (let ((diags (handler-case (parse-document text)
                 (error (e)
                   (format *error-output* "parser error: ~a~%" e)
                   '()))))
    (publish-diagnostics server uri diags)))

;;; --- handlers ----------------------------------------------------------

(defun handle-initialize (server params)
  (declare (ignore server params))
  `(("capabilities"
     . (("textDocumentSync" . 1)            ; full sync
        ("completionProvider"
         . (("triggerCharacters" . ("."))))))))

(defun handle-initialized (server params)
  (declare (ignore server params))
  :null)

(defun handle-shutdown (server params)
  (declare (ignore server params))
  :null)

(defun handle-exit (server params)
  (declare (ignore server params))
  (uiop:quit 0))

(defun handle-did-open (server params)
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (text (get-field td "text"))
         (version (get-field td "version")))
    (setf (gethash uri *documents*)
          (make-document :uri uri :text text :version version
                         :symbols (handler-case (scan-symbols text)
                                    (error (e)
                                      (format *error-output* "scan-symbols error: ~a~%" e)
                                      '()))))
    (reparse-and-publish server uri text)
    :null))

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
                                       (format *error-output* "scan error: ~a~%" e)
                                       '())))
      (reparse-and-publish server uri new-text))
    :null))

(defun handle-did-save (server params)
  (handle-did-change server params))

(defun handle-did-close (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri")))
    (remhash uri *documents*)
    :null))

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
                              (format *error-output* "complete-at error: ~a~%" e)
                              '()))))
        (setf items
              (mapcar (lambda (label)
                        `(("label" . ,label) ("kind" . 14)))   ; 14 = Keyword
                      completions))))
    `(("isIncomplete" . :false)
      ("items" . ,items))))

;;; --- entry point -------------------------------------------------------

(defun run-server ()
  "Start the LSP server on stdio. Blocks until exit."
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
    (jsonrpc:server-listen server :mode :stdio)
    ;; server-listen returns; block until exit handler calls (uiop:quit).
    (loop (sleep 1))))
