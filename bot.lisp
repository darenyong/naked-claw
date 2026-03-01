(defpackage :naked-claw
  (:use :cl)
  (:export :main))

(in-package :naked-claw)

;;; --- Config ---

(defvar *telegram-token* (uiop:getenv "TELEGRAM_TOKEN"))
(defvar *chat-api-url* (or (uiop:getenv "CHAT_API_URL") "https://mlvoca.com/api/generate"))
(defvar *chat-model* (or (uiop:getenv "CHAT_MODEL") "deepseek-r1:1.5b"))
(defvar *compaction-api-url* (or (uiop:getenv "COMPACTION_API_URL") *chat-api-url*))
(defvar *compaction-model* (or (uiop:getenv "COMPACTION_MODEL") *chat-model*))
(defvar *api-key* (or (uiop:getenv "API_KEY") ""))
(defvar *data-dir* (or (uiop:getenv "DATA_DIR") "/data"))
(defvar *max-compact* (parse-integer (or (uiop:getenv "MAX_COMPACT") "20")))

(defun data-file () (merge-pathnames "data.json" (uiop:ensure-directory-pathname *data-dir*)))
(defun digest-file () (merge-pathnames "digest.md" (uiop:ensure-directory-pathname *data-dir*)))

(defun gemini-p (url) (search "googleapis.com" url))

;;; --- Buffer ---

(defun read-buffer ()
  (handler-case
      (with-open-file (s (data-file) :if-does-not-exist nil)
        (if s
            (let ((data (yason:parse s)))
              (gethash "messages" data))
            (list)))
    (error () (list))))

(defun write-buffer (messages)
  (with-open-file (s (data-file) :direction :output :if-exists :supersede)
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "messages" ht) messages)
      (yason:encode ht s))))

(defun append-message (role content &key elapsed-ms)
  (let* ((messages (read-buffer))
         (msg (make-hash-table :test 'equal)))
    (setf (gethash "role" msg) role)
    (setf (gethash "content" msg) content)
    (setf (gethash "ts" msg) (timestamp-now))
    (when elapsed-ms
      (setf (gethash "elapsed_ms" msg) elapsed-ms))
    (write-buffer (append messages (list msg)))))

(defun timestamp-now ()
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            year month day hour min sec)))

;;; --- Digest ---

(defun read-digest ()
  (handler-case
      (let ((text (uiop:read-file-string (digest-file))))
        (string-trim '(#\Space #\Newline #\Return #\Tab) text))
    (error () "")))

(defun write-digest (text)
  (with-open-file (s (digest-file) :direction :output :if-exists :supersede)
    (write-string text s)))

;;; --- LLM ---

(defun strip-think-tags (text)
  (let ((start (search "<think>" text)))
    (if start
        (let ((end (search "</think>" text)))
          (if end
              (string-trim '(#\Space #\Newline #\Return #\Tab)
                           (concatenate 'string
                                        (subseq text 0 start)
                                        (subseq text (+ end 8))))
              text))
        text)))

(defun llm-call (api-url model prompt)
  (let* ((is-gemini (gemini-p api-url))
         (url (if is-gemini
                  (format nil "~A/v1beta/models/~A:generateContent?key=~A"
                          api-url model *api-key*)
                  api-url))
         (body (if is-gemini
                   (with-output-to-string (s)
                     (yason:encode
                      (alexandria:alist-hash-table
                       `(("contents" . ,(vector
                                         (alexandria:alist-hash-table
                                          `(("parts" . ,(vector
                                                         (alexandria:alist-hash-table
                                                          `(("text" . ,prompt))
                                                          :test 'equal))))
                                          :test 'equal))))
                       :test 'equal)
                      s))
                   (with-output-to-string (s)
                     (yason:encode
                      (alexandria:alist-hash-table
                       `(("model" . ,model)
                         ("prompt" . ,prompt)
                         ("stream" . nil)
                         ("think" . nil))
                       :test 'equal)
                      s))))
         (headers (if (and (not is-gemini) (plusp (length *api-key*)))
                      (list (cons "Authorization" (format nil "Bearer ~A" *api-key*)))
                      nil)))
    (multiple-value-bind (body-bytes status-code)
        (drakma:http-request url
                             :method :post
                             :content-type "application/json"
                             :additional-headers headers
                             :content body
                             :want-stream nil)
      (let ((response-text (if (typep body-bytes '(vector (unsigned-byte 8)))
                               (flexi-streams:octets-to-string body-bytes :external-format :utf-8)
                               body-bytes)))
        (unless (= status-code 200)
          (error "LLM API error ~A: ~A" status-code response-text))
        (let ((data (yason:parse response-text)))
          (if is-gemini
              (let* ((candidates (gethash "candidates" data))
                     (first-candidate (aref candidates 0))
                     (content (gethash "content" first-candidate))
                     (parts (gethash "parts" content))
                     (first-part (aref parts 0)))
                (gethash "text" first-part))
              (or (gethash "response" data)
                  (let ((choices (gethash "choices" data)))
                    (when choices
                      (let ((msg (gethash "message" (aref choices 0))))
                        (gethash "content" msg))))
                  response-text)))))))

(defun build-prompt (user-message)
  (let* ((digest (read-digest))
         (messages (read-buffer))
         (recent (last messages 7))
         (parts (list)))
    (when (plusp (length digest))
      (push (format nil "Here is a summary of our previous conversations:~%~A~%~%" digest) parts))
    (when recent
      (push "Recent conversation:~%" parts)
      (dolist (m recent)
        (push (format nil "~A: ~A~%"
                      (if (string= (gethash "role" m) "user") "User" "Assistant")
                      (gethash "content" m))
              parts))
      (push (format nil "~%") parts))
    (push (format nil "User: ~A~%Assistant:" user-message) parts)
    (apply #'concatenate 'string (nreverse parts))))

(defun chat (user-message)
  (let* ((prompt (build-prompt user-message))
         (raw (llm-call *chat-api-url* *chat-model* prompt)))
    (strip-think-tags raw)))

;;; --- Compaction ---

(defun maybe-compact ()
  (let ((messages (read-buffer)))
    (when (>= (length messages) *max-compact*)
      (format t "[~A] Compacting ~A messages...~%" (timestamp-now) *max-compact*)
      (let* ((to-compact (subseq messages 0 *max-compact*))
             (remaining (subseq messages *max-compact*))
             (existing-digest (read-digest))
             (prompt (with-output-to-string (s)
                       (format s "You are a compaction engine. Summarize the following conversation into a concise digest.~%~%")
                       (format s "RULES:~%")
                       (format s "- Capture decisions, facts, preferences, and commitments~%")
                       (format s "- Drop small talk, pleasantries, and filler~%")
                       (format s "- Keep it under 500 words~%")
                       (format s "- Write in plain text, not bullet points~%")
                       (format s "- If there is an existing digest, merge new information into it~%")
                       (format s "- Every fact in the existing digest MUST appear in the new digest~%~%")
                       (when (plusp (length existing-digest))
                         (format s "EXISTING DIGEST:~%~A~%~%" existing-digest))
                       (format s "CONVERSATION:~%")
                       (dolist (m to-compact)
                         (format s "[~A] ~A: ~A~%"
                                 (gethash "ts" m) (gethash "role" m) (gethash "content" m)))
                       (format s "~%DIGEST:"))))
        (handler-case
            (let ((digest (llm-call *compaction-api-url* *compaction-model* prompt)))
              (when (plusp (length (string-trim '(#\Space #\Newline) digest)))
                (write-digest digest)
                (write-buffer remaining)
                (format t "[~A] Compacted: digest ~A chars, ~A messages kept~%"
                        (timestamp-now) (length digest) (length remaining))))
          (error (e)
            (format t "Compaction error: ~A~%" e)))))))

;;; --- Telegram ---

(defvar *update-offset* 0)

(defun tg-api (method &optional params)
  (let* ((url (format nil "https://api.telegram.org/bot~A/~A" *telegram-token* method))
         (body (when params
                 (with-output-to-string (s) (yason:encode params s)))))
    (multiple-value-bind (body-bytes status-code)
        (drakma:http-request url
                             :method :post
                             :content-type "application/json"
                             :content body
                             :want-stream nil
                             :connection-timeout 60
                             :read-timeout 60)
      (let ((response-text (if (typep body-bytes '(vector (unsigned-byte 8)))
                               (flexi-streams:octets-to-string body-bytes :external-format :utf-8)
                               body-bytes)))
        (when (= status-code 200)
          (yason:parse response-text))))))

(defun send-message (chat-id text)
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "chat_id" params) chat-id)
    (setf (gethash "text" params) text)
    (tg-api "sendMessage" params)))

(defun poll-updates ()
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "offset" params) *update-offset*)
    (setf (gethash "timeout" params) 30)
    (let ((response (tg-api "getUpdates" params)))
      (when response
        (let ((results (gethash "result" response)))
          (when (and results (plusp (length results)))
            (loop for update across results
                  for update-id = (gethash "update_id" update)
                  for message = (gethash "message" update)
                  when message
                    do (let ((text (gethash "text" message))
                             (chat (gethash "chat" message))
                             (from (gethash "from" message)))
                         (when text
                           (let ((chat-id (gethash "id" chat))
                                 (first-name (or (gethash "first_name" from) "?")))
                             (handle-message chat-id first-name text))))
                  do (setf *update-offset* (1+ update-id)))))))))

(defun handle-message (chat-id first-name text)
  (format t "[~A] ~A: ~A~%" (timestamp-now) first-name text)
  (append-message "user" text)
  (handler-case
      (let* ((start (get-internal-real-time))
             (reply (chat text))
             (elapsed-ms (round (* 1000 (/ (- (get-internal-real-time) start)
                                           internal-time-units-per-second)))))
        (append-message "assistant" reply :elapsed-ms elapsed-ms)
        (send-message chat-id reply)
        (format t "[~A] Bot (~,1Fs): ~A...~%"
                (timestamp-now) (/ elapsed-ms 1000.0)
                (subseq reply 0 (min 100 (length reply))))
        (maybe-compact))
    (error (e)
      (format t "LLM error: ~A~%" e)
      (send-message chat-id (format nil "Error: ~A" e)))))

;;; --- Main ---

(defun main ()
  (unless *telegram-token*
    (format *error-output* "TELEGRAM_TOKEN is required~%")
    (uiop:quit 1))
  (format t "naked-claw-experiment-cl started.~%")
  (format t "  CHAT_API_URL: ~A~%" *chat-api-url*)
  (format t "  CHAT_MODEL: ~A~%" *chat-model*)
  (format t "  DATA_DIR: ~A~%" *data-dir*)
  (format t "  Digest: ~A~%" (if (plusp (length (read-digest))) "loaded" "none"))
  (format t "  Buffer: ~A messages~%" (length (read-buffer)))
  (loop
    (handler-case (poll-updates)
      (error (e) (format t "Poll error: ~A~%" e)))
    (sleep 1)))
