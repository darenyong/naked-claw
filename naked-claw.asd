(defsystem "naked-claw"
  :version "0.1.0"
  :depends-on ("drakma" "yason" "alexandria")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "primitives")
               (:file "config")
               (:file "buffer")
               (:file "compact")
               (:file "llm")
               (:file "telegram")
               (:file "main")))
