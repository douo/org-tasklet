;;; org-tasklet-archive.el --- 年度归档 -*- lexical-binding: t; -*-

;;; 说明：
;; 归档沿用 Org datetree，文件按年份拆分，避免单个归档文件无限膨胀。

;;; 代码：

(require 'org-tasklet-core)
(require 'org)
(require 'org-archive)

(defun org-tasklet-archive-subtree ()
  "把当前子树归档到年度 datetree。"
  (interactive)
  (org-tasklet--ensure-directory)
  (let ((org-archive-location (org-tasklet-archive-location)))
    (org-archive-subtree-default))
  (org-tasklet--refresh-mode-line-if-present))

(defun org-tasklet--archive-done-in-file (file)
  "归档 FILE 中 DONE 或 CNCL 状态的条目。"
  (let ((count 0))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (goto-char (point-min))
       (while (re-search-forward org-heading-regexp nil t)
         (if (member (org-get-todo-state) org-tasklet-closed-keywords)
             (progn
               (org-tasklet-archive-subtree)
               (setq count (1+ count))
               (goto-char (point-min)))
           (org-end-of-subtree t t))))
      (when (buffer-modified-p)
        (save-buffer)))
    count))

(defun org-tasklet-archive-done ()
  "归档 inbox 和 tasks 中所有已关闭条目。"
  (interactive)
  (org-tasklet-ensure-files)
  (let ((count (+ (org-tasklet--archive-done-in-file (org-tasklet-inbox-file))
                  (org-tasklet--archive-done-in-file (org-tasklet-tasks-file)))))
    (org-tasklet--refresh-mode-line-if-present)
    (message "已归档 %d 个条目" count)
    count))

(provide 'org-tasklet-archive)

;;; org-tasklet-archive.el 到此结束
