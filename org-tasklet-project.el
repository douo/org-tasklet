;;; org-tasklet-project.el --- 项目树状态流 -*- lexical-binding: t; -*-

;;; 说明：
;; 项目只使用 Org 树结构，不维护 DAG、依赖图或额外数据库。

;;; 代码：

(require 'cl-lib)
(require 'org-tasklet-core)
(require 'org)

(defun org-tasklet--heading-has-children-p ()
  "判断当前标题是否有直接或间接子标题。"
  (save-excursion
    (org-back-to-heading t)
    (let ((level (org-outline-level))
          (end (save-excursion (org-end-of-subtree t t))))
      (forward-line 1)
      (and (< (point) end)
           (re-search-forward org-heading-regexp end t)
           (> (org-outline-level) level)))))

(defun org-tasklet-project-p ()
  "判断当前标题是否应按项目处理。"
  (or (string= (org-entry-get nil org-tasklet-project-property) "t")
      (org-tasklet--heading-has-children-p)))

(defun org-tasklet-mark-project ()
  "把当前标题标记为项目。"
  (interactive)
  (org-back-to-heading t)
  (org-set-property org-tasklet-project-property "t")
  (message "已标记为项目：%s" (org-get-heading t t t t)))

(defun org-tasklet--direct-open-child-markers ()
  "返回当前项目下直接子任务的 marker 列表。"
  (save-excursion
    (org-back-to-heading t)
    (let ((parent-level (org-outline-level))
          (end (save-excursion (org-end-of-subtree t t)))
          markers)
      (forward-line 1)
      (while (re-search-forward org-heading-regexp end t)
        (when (and (= (org-outline-level) (1+ parent-level))
                   (member (org-get-todo-state) org-tasklet-open-keywords))
          (push (point-marker) markers)))
      (nreverse markers))))

(defun org-tasklet--direct-open-child-states ()
  "返回当前项目下直接未完成子任务的状态列表。"
  (save-excursion
    (org-back-to-heading t)
    (let ((parent-level (org-outline-level))
          (end (save-excursion (org-end-of-subtree t t)))
          states)
      (forward-line 1)
      (while (re-search-forward org-heading-regexp end t)
        (when (and (= (org-outline-level) (1+ parent-level))
                   (member (org-get-todo-state) org-tasklet-open-keywords))
          (push (org-get-todo-state) states)))
      (nreverse states))))

(defun org-tasklet-project-stuck-p ()
  "判断当前项目是否缺少 NEXT 子任务。"
  (let ((states (org-tasklet--direct-open-child-states)))
    (and states
         (not (member "NEXT" states)))))

(defun org-tasklet-stuck-projects ()
  "返回正式任务文件中缺少 NEXT 的项目列表。"
  (org-tasklet--ensure-file (org-tasklet-tasks-file) "Tasks")
  (let (projects)
    (with-current-buffer (find-file-noselect (org-tasklet-tasks-file))
      (org-with-wide-buffer
       (goto-char (point-min))
       (while (re-search-forward org-heading-regexp nil t)
         (when (and (org-tasklet-project-p)
                    (org-tasklet-project-stuck-p))
           (push (list :title (org-get-heading t t t t)
                       :path (string-join (org-get-outline-path t) " / ")
                       :file (buffer-file-name)
                       :line (line-number-at-pos))
                 projects)))))
    (nreverse projects)))

(defun org-tasklet-reflect-stuck-projects ()
  "显示缺少 NEXT 子任务的项目。"
  (interactive)
  (let ((projects (org-tasklet-stuck-projects))
        (buffer (get-buffer-create "*Org Tasklet Stuck Projects*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "#+TITLE: Stuck Projects\n\n")
        (if projects
            (dolist (project projects)
              (insert "- "
                      (org-link-make-string
                       (format "file:%s::%d"
                               (plist-get project :file)
                               (plist-get project :line))
                       (or (plist-get project :path)
                           (plist-get project :title)))
                      "\n"))
          (insert "没有缺少 NEXT 的项目。\n"))
        (org-mode)
        (setq buffer-read-only t)))
    (pop-to-buffer buffer)))

(defun org-tasklet-refresh-project ()
  "刷新当前项目的 NEXT 状态。"
  (interactive)
  (org-back-to-heading t)
  (unless (org-tasklet-project-p)
    (user-error "当前标题不是项目"))
  (let* ((children (org-tasklet--direct-open-child-markers))
         (next-seen nil)
         (changed 0))
    (dolist (marker children)
      (with-current-buffer (marker-buffer marker)
        (goto-char marker)
        (let ((state (org-get-todo-state)))
          (cond
           ((and (string= state "NEXT") next-seen)
            (org-todo "TODO")
            (setq changed (1+ changed)))
           ((string= state "NEXT")
            (setq next-seen t))))))
    (unless next-seen
      (let ((first (car children)))
        (when first
          (with-current-buffer (marker-buffer first)
            (goto-char first)
            (org-todo "NEXT")
            (setq changed (1+ changed))))))
    (message "项目已刷新，调整 %d 个状态" changed)
    changed))

(defun org-tasklet--project-heading-p-at-point ()
  "在当前位置判断标题是否像项目。"
  (and (org-at-heading-p)
       (org-tasklet-project-p)))

(defun org-tasklet-refresh-all-projects ()
  "刷新正式任务文件中的所有项目。"
  (interactive)
  (org-tasklet--ensure-file (org-tasklet-tasks-file) "Tasks")
  (let ((count 0)
        (changed 0))
    (with-current-buffer (find-file-noselect (org-tasklet-tasks-file))
      (org-with-wide-buffer
       (goto-char (point-min))
       (while (re-search-forward org-heading-regexp nil t)
         (when (org-tasklet--project-heading-p-at-point)
           (setq count (1+ count))
           (setq changed (+ changed (org-tasklet-refresh-project))))))
      (save-buffer))
    (message "已刷新 %d 个项目，调整 %d 个状态" count changed)
    changed))

(defun org-tasklet--goto-nearest-project ()
  "移动到最近的上级项目；找到时返回 t。"
  (let ((found nil))
    (save-match-data
      (while (and (not found) (org-up-heading-safe))
        (when (org-tasklet-project-p)
          (setq found t))))
    found))

(defun org-tasklet-project-done-and-advance ()
  "完成当前项目任务，并刷新最近的上级项目。"
  (interactive)
  (org-back-to-heading t)
  (org-todo "DONE")
  (when (org-tasklet--goto-nearest-project)
    (org-tasklet-refresh-project)))

(provide 'org-tasklet-project)

;;; org-tasklet-project.el 到此结束
