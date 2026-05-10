;;;; lsp/server.lisp — JSON-RPC handlers + run-server.
;;;;
;;;; Scope: completion ONLY. Diagnostics (publishDiagnostics) were
;;;; dropped from this prototype after lem-lsp-mode's typed parsing of
;;;; our publishDiagnostics notification proved hard to land cleanly
;;;; without modifying lem itself. The structural parser still loads
;;;; (and is unit-tested), but no diagnostics are sent over the wire.

(defpackage #:phaverlite-lsp/server
  (:use #:cl)
  (:import-from #:phaverlite-lsp/symbols
                #:scan-symbols)
  (:import-from #:phaverlite-lsp/completion
                #:complete-at)
  (:export #:run-server))
(in-package #:phaverlite-lsp/server)

;;; --- temporary diagnostic log (writes to var/log/lsp-trace.log) ---------
;;; Remove once completion is verified working in lem.

(defvar *log-stream* nil)

(defun log-line (fmt &rest args)
  (when *log-stream*
    (apply #'format *log-stream* fmt args)
    (terpri *log-stream*)
    (force-output *log-stream*)))

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

(defun safe-scan-symbols (text)
  "Scan symbols, returning '() on any error rather than escaping."
  (handler-case (scan-symbols (or text ""))
    (error () '())))

;;; --- handlers ----------------------------------------------------------
;;; Every handler returns a hash-table (encoded as a JSON object), nil
;;; (notifications), or :null. SBCL's debugger is disabled in run-server
;;; so any uncaught condition exits cleanly to stderr instead of hanging.

(defun handle-initialize (server params)
  (declare (ignore server params))
  (log-line "handle-initialize")
  ;; Advertise completion only — no diagnosticProvider (we don't publish
  ;; diagnostics in this prototype) and no fancy fields. Minimal shape that
  ;; lem-lsp-mode's typed parser is willing to accept on this lem version.
  (ht "capabilities"
      (ht "textDocumentSync" 1
          "hoverProvider" (ht)
          "completionProvider"
          (ht "triggerCharacters" (vector ".")))))

(defun handle-initialized (server params)
  (declare (ignore server params))
  (log-line "handle-initialized")
  nil)

(defun handle-shutdown (server params)
  (declare (ignore server params))
  nil)

(defun handle-exit (server params)
  (declare (ignore server params))
  (uiop:quit 0))

(defun handle-did-open (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (text (get-field td "text"))
         (version (get-field td "version")))
    (log-line "handle-did-open uri=~a text-len=~a" uri (length text))
    (setf (gethash uri *documents*)
          (make-document :uri uri :text text :version version
                         :symbols (safe-scan-symbols text))))
  nil)

(defun handle-did-change (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (changes (get-field params "contentChanges"))
         ;; Full sync — last change is the new full text.
         (new-text (get-field (car (last changes)) "text"))
         (doc (gethash uri *documents*)))
    (when doc
      (setf (document-text doc) new-text
            (document-symbols doc) (safe-scan-symbols new-text))))
  nil)

(defun handle-did-save (server params)
  (handle-did-change server params))

(defun handle-did-close (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri")))
    (remhash uri *documents*))
  nil)

(defun handle-hover (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (pos (get-field params "position"))
         (line (get-field pos "line"))
         (character (get-field pos "character")))
    (log-line "handle-hover uri=~a line=~a char=~a" uri line character))
  (ht "contents" "PHAVerLite LSP: it's alive"))

(defun handle-completion (server params)
  (declare (ignore server))
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (pos (get-field params "position"))
         (line (get-field pos "line"))
         (character (get-field pos "character"))
         (doc (gethash uri *documents*))
         (items (vector)))
    (log-line "handle-completion uri=~a line=~a char=~a doc?=~a"
              uri line character (not (null doc)))
    (when doc
      (let* ((offset (line-character-to-offset (document-text doc) line character))
             (completions (handler-case
                              (complete-at (document-text doc) offset
                                           (document-symbols doc))
                            (error () '()))))
        (log-line "handle-completion offset=~a returning ~a items"
                  offset (length completions))
        (setf items
              (coerce
               (mapcar (lambda (label)
                         (ht "label" label "kind" 14))   ; 14 = Keyword
                       completions)
               'vector))))
    ;; Use vector for items so yason emits `[]` even when empty.
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
  (ensure-directories-exist "var/log/")
  (setf *log-stream*
        (open "var/log/lsp-trace.log"
              :direction :output
              :if-exists :supersede
              :if-does-not-exist :create))
  ;; Override jsonrpc/transport/stdio's receive-message-using-transport
  ;; with a BYTE-aware read. Upstream's read-message uses (read-sequence body
  ;; stream) which reads CHARS, but LSP's Content-Length is BYTES. With any
  ;; multi-byte UTF-8 in the body, the char-based read overshoots the body
  ;; byte boundary and corrupts framing for the next message, silently
  ;; killing the server. Same patch lem applies for its own LSP frontend
  ;; (.lem-ref/frontends/server/jsonrpc-stdio-patch.lisp).
  (defmethod jsonrpc/transport/interface:receive-message-using-transport
      ((transport jsonrpc/transport/stdio:stdio-transport) connection)
    (let* ((stream (jsonrpc/connection:connection-stream connection))
           (headers (jsonrpc/request-response::read-headers stream))
           (length (ignore-errors
                    (parse-integer (gethash "content-length" headers)))))
      (when length
        (let ((body
                (with-output-to-string (out)
                  (loop
                    :for c := (read-char stream)
                    :do (write-char c out)
                        (decf length (babel:string-size-in-octets (string c)))
                        (when (<= length 0) (return))))))
          (jsonrpc/request-response:parse-message body)))))
  (let ((server (jsonrpc:make-server)))
    (jsonrpc:expose server "initialize"              (lambda (p) (handle-initialize server p)))
    (jsonrpc:expose server "initialized"             (lambda (p) (handle-initialized server p)))
    (jsonrpc:expose server "shutdown"                (lambda (p) (handle-shutdown server p)))
    (jsonrpc:expose server "exit"                    (lambda (p) (handle-exit server p)))
    (jsonrpc:expose server "textDocument/didOpen"    (lambda (p) (handle-did-open server p)))
    (jsonrpc:expose server "textDocument/didChange"  (lambda (p) (handle-did-change server p)))
    (jsonrpc:expose server "textDocument/didSave"    (lambda (p) (handle-did-save server p)))
    (jsonrpc:expose server "textDocument/didClose"   (lambda (p) (handle-did-close server p)))
    (jsonrpc:expose server "textDocument/hover"      (lambda (p) (handle-hover server p)))
    (jsonrpc:expose server "textDocument/completion" (lambda (p) (handle-completion server p)))
    ;; server-listen runs the reading loop in THIS thread (per stdio
    ;; transport's start-server impl), spawning a separate processing
    ;; thread. It blocks until stdin EOF; no extra (loop (sleep 1)) needed.
    (handler-case
        (jsonrpc:server-listen server :mode :stdio)
      (end-of-file ()
        (log-line "server-listen returned: END-OF-FILE on stdin")
        nil)
      (error (e)
        (log-line "server-listen returned: ERROR ~A: ~A" (type-of e) e)
        nil)
      (:no-error (&rest values)
        (declare (ignore values))
        (log-line "server-listen returned cleanly (no error)")
        nil))))
