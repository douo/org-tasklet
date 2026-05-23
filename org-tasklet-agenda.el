;;; org-tasklet-agenda.el --- 日程视图和状态快捷键 -*- lexical-binding: t; -*-

;;; 说明：
;; 日程视图只在用户打开时加载，避免拖慢 Emacs 启动。

;;; 代码：

(require 'cl-lib)
(require 'org-tasklet-core)
(require 'org)
(require 'org-agenda)

(defun org-tasklet--agenda-files ()
  "返回插件参与 agenda 的文件列表。"
  (org-tasklet-ensure-files)
  (list (org-tasklet-inbox-file)
        (org-tasklet-tasks-file)))

(defun org-tasklet--agenda-skip-closed ()
  "在 agenda 中跳过已关闭条目。"
  (when (member (org-get-todo-state) org-tasklet-closed-keywords)
    (or (outline-next-heading) (point-max))))

(defun org-tasklet-engage ()
  "显示 Tasklet 总览 agenda。"
  (interactive)
  (let* ((inbox (org-tasklet-inbox-file))
         (tasks (org-tasklet-tasks-file))
         (org-agenda-files (org-tasklet--agenda-files))
         (org-agenda-custom-commands
          `(("t" "Tasklet"
             ((agenda ""
                      ((org-agenda-span 1)
                       (org-agenda-start-day nil)
                       (org-agenda-skip-additional-timestamps-same-entry t)
                       (org-agenda-overriding-header "今天")))
              (tags "LEVEL=1"
                    ((org-agenda-files '(,inbox))
                     (org-agenda-skip-function #'org-tasklet--agenda-skip-closed)
                     (org-agenda-overriding-header "Inbox")))
              (todo "NEXT"
                    ((org-agenda-files '(,tasks))
                     (org-agenda-overriding-header "项目下一步")))
              (todo "TODO"
                    ((org-agenda-files '(,tasks))
                     (org-agenda-overriding-header "普通任务和项目待办"))))
             ((org-agenda-inhibit-startup t))))))
    (org-agenda nil "t")
    (goto-char (point-min))))

(defun org-tasklet-show-next ()
  "显示所有 NEXT 条目。"
  (interactive)
  (let ((org-agenda-files (list (org-tasklet-tasks-file)))
        (org-agenda-custom-commands
         '(("n" "Tasklet NEXT"
            ((todo "NEXT" ((org-agenda-overriding-header "项目下一步"))))
            ((org-agenda-inhibit-startup t))))))
    (org-agenda nil "n")
    (goto-char (point-min))))

(defun org-tasklet-agenda-todo-dwim (&optional arg)
  "在 agenda 中切换 TODO 状态；ARG 非空时回退到原生命令。"
  (interactive "P")
  (if arg
      (call-interactively #'org-agenda-todo)
    (let ((state (org-get-at-bol 'todo-state)))
      (cond
       ((member state org-tasklet-open-keywords)
        (org-agenda-todo "DONE"))
       ((member state org-tasklet-closed-keywords)
        (org-agenda-todo "TODO"))
       (t
        (call-interactively #'org-agenda-todo))))))

(provide 'org-tasklet-agenda)

;;; org-tasklet-agenda.el 到此结束
