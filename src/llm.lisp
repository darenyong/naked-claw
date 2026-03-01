;;; LLM integration — prompt building, API calls (Gemini + Ollama)

(in-package :naked-claw)

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
         (body (to-json
                (if is-gemini
                    (json-obj "contents" (vector (json-obj "parts" (vector (json-obj "text" prompt)))))
                    (json-obj "model" model "prompt" prompt "stream" nil "think" nil))))
         (headers (when (and (not is-gemini) (plusp (length *api-key*)))
                    `(("Authorization" . ,(format nil "Bearer ~A" *api-key*))))))
    (multiple-value-bind (data status raw-text) (post-json url body :headers headers)
      (unless (= status 200)
        (error "LLM API error ~A: ~A" status raw-text))
      (if is-gemini
          ($ data "candidates" 0 "content" "parts" 0 "text")
          (or ($ data "response")
              (when ($ data "choices") ($ data "choices" 0 "message" "content"))
              raw-text)))))

(defun build-prompt (user-message)
  (let* ((digest (read-digest))
         (recent (last (read-buffer) 7))
         (parts (list)))
    (when (plusp (length digest))
      (push (format nil "Here is a summary of our previous conversations:~%~A~%~%" digest) parts))
    (when recent
      (push "Recent conversation:~%" parts)
      (dolist (m recent)
        (push (format nil "~A: ~A~%"
                      (if (string= ($ m "role") "user") "User" "Assistant")
                      ($ m "content"))
              parts))
      (push (format nil "~%") parts))
    (push (format nil "User: ~A~%Assistant:" user-message) parts)
    (apply #'concatenate 'string (nreverse parts))))

(defun chat (user-message)
  (strip-think-tags (llm-call *chat-api-url* *chat-model* (build-prompt user-message))))
