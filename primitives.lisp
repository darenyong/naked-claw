(in-package :naked-claw)

(setf yason:*parse-json-arrays-as-vectors* t)

(defun json-obj (&rest pairs)
  "Build a hash table from flat key/value pairs: (json-obj \"k\" v \"k2\" v2)"
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr do (setf (gethash k ht) v))
    ht))

(defun to-json (obj)
  (with-output-to-string (s) (yason:encode obj s)))

(defun post-json (url body &key headers timeout)
  "POST JSON, return (values parsed-response status-code raw-text)."
  (multiple-value-bind (raw status)
      (drakma:http-request url
                           :method :post
                           :content-type "application/json"
                           :additional-headers headers
                           :content body
                           :want-stream nil
                           :external-format-out :utf-8
                           :external-format-in :utf-8
                           :connection-timeout (or timeout 30))
    (let ((text (if (typep raw '(vector (unsigned-byte 8)))
                    (flexi-streams:octets-to-string raw :external-format :utf-8)
                    raw)))
      (values (yason:parse text) status text))))

(defun $ (obj &rest keys)
  "Nested hash-table access: ($ data \"candidates\" 0 \"content\")"
  (reduce (lambda (o k)
            (etypecase k
              (string (gethash k o))
              (integer (aref o k))))
          keys :initial-value obj))
