;;;; lsp/server.lisp — JSON-RPC handlers + run-server.
;;;;
;;;; Scope: hover (proof of life) + completion. Diagnostics are out of
;;;; scope for this prototype.

(defpackage #:phaverlite-lsp/server
  (:use #:cl)
  (:import-from #:phaverlite-lsp/symbols
                #:scan-symbols)
  (:import-from #:phaverlite-lsp/completion
                #:complete-at)
  (:import-from #:phaverlite-lsp/parser
                #:parse-document
                #:diagnostic-start-line
                #:diagnostic-start-col
                #:diagnostic-end-line
                #:diagnostic-end-col
                #:diagnostic-severity
                #:diagnostic-message)
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

(defun ht (&rest pairs)
  "Build a string-keyed hash-table (yason → JSON object). PAIRS are
   alternating KEY VALUE."
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k h) v))
    h))

(defun line-character-to-offset (text line character)
  "LSP positions are 0-based (line, character). Convert to a char offset
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

;;; --- diagnostics -------------------------------------------------------

(defun severity-to-lsp (sev)
  "Map :error/:warning to LSP DiagnosticSeverity (1=Error, 2=Warning)."
  (case sev
    (:error 1)
    (:warning 2)
    (t 3)))                             ; Info fallback

(defun diagnostic-to-lsp (d)
  (ht "range" (ht "start" (ht "line" (diagnostic-start-line d)
                              "character" (diagnostic-start-col d))
                  "end"   (ht "line" (diagnostic-end-line d)
                              "character" (diagnostic-end-col d)))
      "severity" (severity-to-lsp (diagnostic-severity d))
      "source" "phaverlite-lsp"
      "message" (diagnostic-message d)))

(defun publish-diagnostics (server uri text)
  "Parse TEXT, send a textDocument/publishDiagnostics notification.
   Always sends, even with an empty diagnostics array — that's how the
   client clears stale squiggles after a fix. Vector (not list) so
   yason emits `[]` for the empty case rather than `null`."
  (let* ((diags (handler-case (parse-document (or text ""))
                  (error () '())))
         (items (coerce (mapcar #'diagnostic-to-lsp diags) 'vector)))
    (handler-case
        (jsonrpc:notify server
                        "textDocument/publishDiagnostics"
                        (ht "uri" uri "diagnostics" items))
      ;; If we're called outside a handler (no *connection*), notify errors;
      ;; that's fine for tests / direct-driver flows where there's no client.
      (error () nil))))

;;; --- handlers ----------------------------------------------------------
;;; Every handler returns a hash-table (encoded as a JSON object) or nil
;;; (for notifications). SBCL's debugger is disabled in run-server, so
;;; any uncaught condition exits the process to stderr instead of writing
;;; debugger prompts onto the JSON-RPC stream.

(defun handle-initialize (server params)
  (declare (ignore server params))
  (ht "capabilities"
      (ht "textDocumentSync" 1
          "hoverProvider" (ht)
          "completionProvider"
          (ht "triggerCharacters" (vector ".")))))

(defun handle-initialized (server params)
  (declare (ignore server params))
  nil)

(defun handle-shutdown (server params)
  (declare (ignore server params))
  nil)

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
                         :symbols (safe-scan-symbols text)))
    (publish-diagnostics server uri text))
  nil)

(defun apply-incremental-change (text change)
  "Apply one LSP incremental contentChange (a hash-table with `range`
   and `text`) to TEXT. `range` has `start` and `end` (each line/character)."
  (let* ((range (get-field change "range"))
         (new-text (get-field change "text"))
         (start (get-field range "start"))
         (end (get-field range "end"))
         (start-offset (line-character-to-offset
                        text (get-field start "line") (get-field start "character")))
         (end-offset (line-character-to-offset
                      text (get-field end "line") (get-field end "character"))))
    (concatenate 'string
                 (subseq text 0 start-offset)
                 (or new-text "")
                 (subseq text end-offset))))

(defun handle-did-change (server params)
  ;; Lem's lsp-mode hard-codes incremental contentChange events regardless
  ;; of the sync mode we advertise — every keystroke arrives as one event
  ;; with `range` + small `text`. We must apply each event to the stored
  ;; document text, not replace the whole document with the event payload.
  (let* ((td (get-field params "textDocument"))
         (uri (get-field td "uri"))
         (changes (get-field params "contentChanges"))
         (doc (gethash uri *documents*)))
    (when doc
      (let ((text (document-text doc)))
        (when (typep changes 'sequence)
          (map nil (lambda (change)
                     (cond
                       ((and (hash-table-p change)
                             (gethash "range" change))
                        (setf text (apply-incremental-change text change)))
                       ;; Fallback: full-sync event has no range, just text.
                       ((hash-table-p change)
                        (setf text (or (gethash "text" change) "")))))
                changes))
        (setf (document-text doc) text
              (document-symbols doc) (safe-scan-symbols text))
        (publish-diagnostics server uri text))))
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
  (declare (ignore server params))
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
    (when doc
      (let* ((offset (line-character-to-offset (document-text doc) line character))
             (completions (handler-case
                              (complete-at (document-text doc) offset
                                           (document-symbols doc))
                            (error () '()))))
        (setf items
              (coerce
               (mapcar (lambda (label)
                         (ht "label" label "kind" 14))   ; 14 = Keyword
                       completions)
               'vector))))
    ;; CompletionList: isIncomplete is required per LSP — omitting it leaves
    ;; lem's typed completion-list slot unbound and downstream code crashes
    ;; with "<HASH-TABLE> is not a NIL". yason:false symbol so it serializes
    ;; as JSON `false` (yason encodes Lisp NIL as `null`, not `false`).
    (ht "isIncomplete" 'yason:false "items" items)))

;;; --- byte-aware stdio transport patch ----------------------------------
;;; Override jsonrpc/transport/stdio's receive-message-using-transport
;;; with a BYTE-aware read. Upstream's read-message uses (read-sequence
;;; body stream) which reads CHARS, but LSP's Content-Length is BYTES.
;;; With any multi-byte UTF-8 in the body, the char-based read overshoots
;;; the body's byte boundary, corrupting framing for the next message
;;; and silently killing the server. Same patch lem applies for its own
;;; LSP frontend (.lem-ref/frontends/server/jsonrpc-stdio-patch.lisp).
;;;
;;; Top-level (not inside run-server) so the defmethod is registered
;;; once at image build time — avoids "redefining" warnings on each
;;; server start.

(defmethod jsonrpc/transport/interface:receive-message-using-transport
    ((transport jsonrpc/transport/stdio:stdio-transport) connection)
  (let* ((stream (jsonrpc/connection:connection-stream connection))
         ;; read-headers errors with end-of-file when lem closes the pipe
         ;; on shutdown — that's the normal exit path, return nil so the
         ;; reading loop terminates quietly instead of leaving a backtrace.
         (headers (handler-case (jsonrpc/request-response::read-headers stream)
                    (end-of-file () nil)))
         (length (and headers
                      (ignore-errors
                       (parse-integer (gethash "content-length" headers))))))
    (when length
      (handler-case
          (let ((body
                  (with-output-to-string (out)
                    (loop
                      :for c := (read-char stream)
                      :do (write-char c out)
                          (decf length (babel:string-size-in-octets (string c)))
                          (when (<= length 0) (return))))))
            (jsonrpc/request-response:parse-message body))
        (end-of-file () nil)))))

;;; --- entry point -------------------------------------------------------

(defun run-server ()
  "Start the LSP server on stdio. Blocks on the reading loop until
   the exit handler calls (uiop:quit 0) or stdin reaches EOF."
  ;; Disable SBCL's interactive debugger. If a handler raises an uncaught
  ;; condition, the debugger prompt would otherwise write to stdout (the
  ;; LSP transport), corrupting the JSON-RPC stream.
  #+sbcl (sb-ext:disable-debugger)
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
    (jsonrpc:server-listen server :mode :stdio)))
