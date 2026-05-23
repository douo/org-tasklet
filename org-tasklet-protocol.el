;;; org-tasklet-protocol.el --- org-protocol 捕获兼容层 -*- lexical-binding: t; -*-

;;; 说明：
;; 这里保留 gtd-capture 旧协议，避免马上修改浏览器快捷键。

;;; 代码：

(require 'cl-lib)
(require 'org-tasklet-core)
(require 'org-protocol)

(declare-function org-tasklet-capture-inbox "org-tasklet-capture")
(declare-function org-tasklet-capture-read-later "org-tasklet-capture")

(defun org-tasklet--protocol-parts (info)
  "把 org-protocol 传入的 INFO 解析成 plist。"
  (let ((parts (org-protocol-parse-parameters info)))
    (if (and (consp parts) (keywordp (car parts)))
        parts
      (let ((keys (if (and (car parts) (= 1 (length (car parts))))
                      '(:template :url :title :body)
                    '(:url :title :body))))
        (org-protocol-assign-parameters parts keys)))))

(defun org-tasklet-protocol-capture (info)
  "处理 org-protocol 捕获请求。"
  (require 'org-tasklet-capture)
  (let* ((parts (org-tasklet--protocol-parts info))
         (template (plist-get parts :template))
         (url (plist-get parts :url))
         (title (plist-get parts :title))
         (body (plist-get parts :body)))
    (if (or url (string= template "r"))
        (org-tasklet-capture-read-later url title body)
      (org-tasklet-capture-inbox title body))
    nil))

(defun org-tasklet--protocol-entry (protocol)
  "构造 PROTOCOL 对应的 org-protocol 注册条目。"
  `(,(concat "org-tasklet-" protocol)
    :protocol ,protocol
    :function org-tasklet-protocol-capture))

(defun org-tasklet--remove-protocol (protocol)
  "从 `org-protocol-protocol-alist' 中移除 PROTOCOL 的旧注册。"
  (setq org-protocol-protocol-alist
        (cl-remove-if
         (lambda (entry)
           (string= (plist-get (cdr entry) :protocol) protocol))
         org-protocol-protocol-alist)))

(defun org-tasklet-register-org-protocol ()
  "注册 Tasklet 的 org-protocol 处理器。"
  (interactive)
  (dolist (protocol (append org-tasklet-protocols org-tasklet-legacy-protocols))
    (org-tasklet--remove-protocol protocol)
    (add-to-list 'org-protocol-protocol-alist
                 (org-tasklet--protocol-entry protocol)
                 t))
  (message "已注册 org-tasklet org-protocol：%s"
           (string-join (append org-tasklet-protocols org-tasklet-legacy-protocols)
                        ", ")))

(provide 'org-tasklet-protocol)

;;; org-tasklet-protocol.el 到此结束
