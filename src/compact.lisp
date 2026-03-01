;;; Compaction — digest old messages to stay within context window

(in-package :naked-claw)

(defun read-digest ()
  (handler-case
      (string-trim '(#\Space #\Newline #\Return #\Tab)
                   (uiop:read-file-string (digest-file)))
    (error () "")))

(defun write-digest (text)
  (with-open-file (s (digest-file) :direction :output :if-exists :supersede)
    (write-string text s)))

(defun maybe-compact ()
  (let ((messages (read-buffer)))
    (when (>= (length messages) *max-compact*)
      (format t "[~A] Compacting ~A messages...~%" (timestamp-now) *max-compact*)
      (let* ((to-compact (subseq messages 0 *max-compact*))
             (remaining (subseq messages *max-compact*))
             (existing (read-digest))
             (prompt (with-output-to-string (s)
                       (format s "You are a compaction engine. Summarize the following conversation into a concise digest.~%~%")
                       (format s "RULES:~%- Capture decisions, facts, preferences, and commitments~%")
                       (format s "- Drop small talk, pleasantries, and filler~%- Keep it under 500 words~%")
                       (format s "- Write in plain text, not bullet points~%")
                       (format s "- If there is an existing digest, merge new information into it~%")
                       (format s "- Every fact in the existing digest MUST appear in the new digest~%~%")
                       (when (plusp (length existing))
                         (format s "EXISTING DIGEST:~%~A~%~%" existing))
                       (format s "CONVERSATION:~%")
                       (dolist (m to-compact)
                         (format s "[~A] ~A: ~A~%" ($ m "ts") ($ m "role") ($ m "content")))
                       (format s "~%DIGEST:"))))
        (handler-case
            (let ((digest (llm-call *compaction-api-url* *compaction-model* prompt)))
              (when (plusp (length (string-trim '(#\Space #\Newline) digest)))
                (write-digest digest)
                (write-buffer remaining)
                (format t "[~A] Compacted: digest ~A chars, ~A messages kept~%"
                        (timestamp-now) (length digest) (length remaining))))
          (error (e) (format t "Compaction error: ~A~%" e)))))))
