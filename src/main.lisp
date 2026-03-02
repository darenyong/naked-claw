;;; Entry point — load config, start polling loop

(in-package :naked-claw)

(defun main ()
  (load-config)
  (unless (and *telegram-token* *chat-api-url* *chat-model*)
    (format *error-output* "Required: TELEGRAM_TOKEN, CHAT_API_URL, CHAT_MODEL~%")
    (uiop:quit 1))
  (format t "naked-claw started.~%")
  (format t "  CHAT_API_URL: ~A~%" *chat-api-url*)
  (format t "  CHAT_MODEL: ~A~%" *chat-model*)
  (format t "  DATA_DIR: ~A~%" *data-dir*)
  (format t "  Digest: ~A~%" (if (plusp (length (read-digest))) "loaded" "none"))
  (format t "  Buffer: ~A messages~%" (length (read-buffer)))
  (loop
    (handler-case (poll-updates)
      (error (e) (format t "Poll error: ~A~%" e)))
    (sleep 1)))
