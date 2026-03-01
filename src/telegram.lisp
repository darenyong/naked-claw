;;; Telegram bot — long-polling, message dispatch

(in-package :naked-claw)

(defvar *update-offset* 0)

(defun tg-api (method &optional params)
  (let ((url (format nil "https://api.telegram.org/bot~A/~A" *telegram-token* method)))
    (multiple-value-bind (data status)
        (post-json url (when params (to-json params)) :timeout 60)
      (when (= status 200) data))))

(defun send-message (chat-id text)
  (tg-api "sendMessage" (json-obj "chat_id" chat-id "text" text)))

(defun poll-updates ()
  (let ((data (tg-api "getUpdates" (json-obj "offset" *update-offset* "timeout" 30))))
    (when data
      (let ((results ($ data "result")))
        (when (and results (plusp (length results)))
          (loop for update across results
                for update-id = ($ update "update_id")
                for message = ($ update "message")
                when message
                  do (let ((text ($ message "text")))
                       (when text
                         (handle-message ($ message "chat" "id")
                                         (or ($ message "from" "first_name") "?")
                                         text)))
                do (setf *update-offset* (1+ update-id))))))))

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
