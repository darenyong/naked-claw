;;; Build script — loads deps via Quicklisp and compiles standalone binary

(load "~/quicklisp/setup.lisp")

;;; Load dependencies
(ql:quickload '("drakma" "yason" "alexandria") :silent t)

;;; Load our system
(push (truename ".") asdf:*central-registry*)
(asdf:load-system "naked-claw")

;;; Compile standalone binary
(sb-ext:save-lisp-and-die "naked-claw"
                          :toplevel #'naked-claw:main
                          :executable t
                          :compression t)
