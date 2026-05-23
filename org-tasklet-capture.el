;;; org-tasklet-capture.el --- 捕获和打开任务文件 -*- lexical-binding: t; -*-

;;; 说明：
;; 捕获直接追加到 Org 文件，避免在启动路径里提前加载 org-capture。

;;; 代码：

(require 'org-tasklet-core)
(require 'org)
(require 'org-capture)

(defcustom org-tasklet-capture-templates
  `(("i" "Inbox"
     entry (file ,#'org-tasklet-capture-inbox-file)
     "* TODO %?\n:PROPERTIES:\n:CREATED: %(org-tasklet--inactive-timestamp)\n:END:\n\n%i"
     :empty-lines 1
     :kill-buffer t)
    ("l" "Inbox with link"
     entry (file ,#'org-tasklet-capture-inbox-file)
     "* TODO %?\n:PROPERTIES:\n:CREATED: %(org-tasklet--inactive-timestamp)\n:END:\n\n%i\n%a"
     :empty-lines 1
     :kill-buffer t)
    ("r" "Read later"
     entry (file ,#'org-tasklet-capture-inbox-file)
     "* TODO %a :read:\n:PROPERTIES:\n:CREATED: %(org-tasklet--inactive-timestamp)\n:END:\n\n%i\n%?"
     :empty-lines 1
     :kill-buffer t))
  "Tasklet 捕获模板。"
  :type 'sexp
  :group 'org-tasklet)

(defmacro org-tasklet-with-capture (&rest body)
  "使用 Tasklet 捕获模板执行 BODY。"
  (declare (debug t) (indent 0))
  `(let ((org-capture-templates org-tasklet-capture-templates))
     ,@body))

(defun org-tasklet--region-text ()
  "返回当前选区文本；没有选区时返回 nil。"
  (when (use-region-p)
    (buffer-substring-no-properties (region-beginning) (region-end))))

(defun org-tasklet-capture-inbox-file ()
  "返回已确保存在的收件箱文件路径。"
  (org-tasklet--ensure-file (org-tasklet-inbox-file) "Inbox"))

(defun org-tasklet-capture (&optional goto keys)
  "使用 Tasklet 模板调用 `org-capture'。"
  (interactive)
  (org-tasklet-ensure-files)
  (org-tasklet-with-capture
    (org-capture goto keys)))

(defun org-tasklet--entry-text (title &optional body tags)
  "生成普通任务的 Org 条目文本。"
  (let ((tag-text (if tags (concat " :" (string-join tags ":") ":") "")))
    (concat "* TODO " (org-tasklet--clean-title title) tag-text "\n"
            ":PROPERTIES:\n"
            ":CREATED: " (org-tasklet--inactive-timestamp) "\n"
            ":END:\n"
            (when (and body (not (string-empty-p (string-trim body))))
              (concat "\n" body "\n"))
            "\n")))

(defun org-tasklet--read-later-entry-text (url title body)
  "生成稍后阅读任务的 Org 条目文本。"
  (let* ((safe-url (or url ""))
         (safe-title (org-tasklet--clean-title (or title safe-url)))
         (link (if (string-empty-p safe-url)
                   safe-title
                 (org-link-make-string safe-url safe-title))))
    (concat "* TODO " link " :" org-tasklet-read-later-tag ":\n"
            ":PROPERTIES:\n"
            ":CREATED: " (org-tasklet--inactive-timestamp) "\n"
            (unless (string-empty-p safe-url)
              (concat ":SOURCE: " safe-url "\n"))
            ":END:\n"
            (when (and body (not (string-empty-p (string-trim body))))
              (concat "\n" body "\n"))
            "\n")))

(defun org-tasklet-capture-inbox (title &optional body tags)
  "快速捕获 TITLE 到收件箱。"
  (interactive
   (list (read-string "任务: ")
         (org-tasklet--region-text)
         nil))
  (org-tasklet--append-to-file
   (org-tasklet-inbox-file)
   (org-tasklet--entry-text title body tags)
   "Inbox")
  (org-tasklet--refresh-mode-line-if-present)
  (message "已捕获到 inbox：%s" (org-tasklet--clean-title title)))

(defun org-tasklet-capture-read-later (url title &optional body)
  "把 URL、TITLE 和 BODY 捕获为稍后阅读条目。"
  (interactive
   (let ((url (read-string "URL: " (or (thing-at-point 'url t) ""))))
     (list url
           (read-string "标题: " nil nil url)
           (org-tasklet--region-text))))
  (org-tasklet--append-to-file
   (org-tasklet-inbox-file)
   (org-tasklet--read-later-entry-text url title body)
   "Inbox")
  (org-tasklet--refresh-mode-line-if-present)
  (message "已捕获稍后阅读：%s" (org-tasklet--clean-title title)))

(defun org-tasklet-open-inbox ()
  "打开收件箱文件。"
  (interactive)
  (org-tasklet--ensure-file (org-tasklet-inbox-file) "Inbox")
  (find-file (org-tasklet-inbox-file)))

(defun org-tasklet-open-tasks ()
  "打开正式任务文件。"
  (interactive)
  (org-tasklet--ensure-file (org-tasklet-tasks-file) "Tasks")
  (find-file (org-tasklet-tasks-file)))

(provide 'org-tasklet-capture)

;;; org-tasklet-capture.el 到此结束
