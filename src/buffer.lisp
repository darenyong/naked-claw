;;; Message buffer — JSON file read/write/append

(in-package :naked-claw)

(defun read-buffer ()
  (handler-case
      (with-open-file (s (data-file) :if-does-not-exist nil)
        (if s (coerce ($ (yason:parse s) "messages") 'list) (list)))
    (error () (list))))

(defun write-buffer (messages)
  (with-open-file (s (data-file) :direction :output :if-exists :supersede)
    (yason:encode (json-obj "messages" messages) s)))

(defun append-message (role content &key elapsed-ms)
  (let ((msg (json-obj "role" role "content" content "ts" (timestamp-now))))
    (when elapsed-ms (setf (gethash "elapsed_ms" msg) elapsed-ms))
    (write-buffer (append (read-buffer) (list msg)))))

(defun timestamp-now ()
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            year month day hour min sec)))
