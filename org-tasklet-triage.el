;;; org-tasklet-triage.el --- 按分类整理当前 inbox 条目 -*- lexical-binding: t; -*-

;;; 说明：
;; 本模块参考 org-gtd 的分类语义，但只使用 Org 原生结构保存数据。
;; 整理入口是一次性命令：在当前 inbox item 上选择分类，然后移动或归档。

;;; 代码：

(require 'cl-lib)
(require 'org-tasklet-core)
(require 'org-tasklet-archive)
(require 'org-tasklet-project)
(require 'org)

(defcustom org-tasklet-triage-ask-tags t
  "整理 inbox 条目时是否提示编辑 tags。"
  :type 'boolean
  :group 'org-tasklet)

(defun org-tasklet--show-all ()
  "展开当前 Org 缓冲区的全部内容。"
  (if (fboundp 'org-fold-show-all)
      (funcall #'org-fold-show-all)
    (funcall (intern "org-show-all"))))

(defun org-tasklet-triage ()
  "打开 inbox 文件。"
  (interactive)
  (find-file (org-tasklet--ensure-file (org-tasklet-inbox-file) "Inbox"))
  (org-mode)
  (org-tasklet--show-all)
  (goto-char (point-min))
  (re-search-forward org-heading-regexp nil t)
  (message "在当前条目上运行 org-tasklet-triage-current-item 进行分类整理"))

(defun org-tasklet--organize-entry (type)
  "返回 TYPE 对应的整理分类配置。"
  (or (assq type org-tasklet-organize-types)
      (user-error "未知整理分类：%s" type)))

(defun org-tasklet--organize-entry-plist (type)
  "返回 TYPE 对应的 plist。"
  (cdr (org-tasklet--organize-entry type)))

(defun org-tasklet--organize-entry-label (entry)
  "返回分类 ENTRY 的显示名称。"
  (or (plist-get (cdr entry) :label)
      (symbol-name (car entry))))

(defun org-tasklet--organize-labels ()
  "返回整理分类的候选名称。"
  (mapcar #'org-tasklet--organize-entry-label org-tasklet-organize-types))

(defun org-tasklet--organize-type-by-label (label)
  "按 LABEL 查找整理分类。"
  (catch 'found
    (dolist (entry org-tasklet-organize-types)
      (when (string= label (org-tasklet--organize-entry-label entry))
        (throw 'found (car entry))))))

(defun org-tasklet--read-organize-type ()
  "读取当前条目的整理分类。"
  (let* ((default "Action")
         (title (org-get-heading t t t t))
         (prompt (if (and title (not (string-empty-p title)))
                     (format "分类当前 item「%s」: " title)
                   "分类当前 item: "))
         (label (completing-read prompt
                                  (org-tasklet--organize-labels)
                                  nil t nil nil default)))
    (org-tasklet--organize-type-by-label label)))

(defun org-tasklet--normalize-organize-type (type)
  "把旧动作符号或 nil 规范化为整理分类 TYPE。"
  (pcase type
    ('nil nil)
    ('move 'action)
    ('make-project 'project)
    (_ type)))

(defun org-tasklet--ensure-current-inbox-item ()
  "确认当前光标位于 inbox 的一个 Org 条目内。"
  (unless (org-tasklet-inbox-buffer-p)
    (user-error "只能处理 Tasklet inbox 中的当前 item：%s"
                (org-tasklet-inbox-file)))
  (unless (derived-mode-p 'org-mode)
    (user-error "当前 buffer 不是 Org mode"))
  (when (org-before-first-heading-p)
    (user-error "当前光标不在 Org item 中"))
  (org-back-to-heading t))

(defun org-tasklet--apply-current-tags (tags interactivep)
  "给当前标题应用 TAGS；INTERACTIVEP 非 nil 时调用 Org 的 tags 编辑命令。"
  (when tags
    (org-set-tags tags))
  (when (and interactivep org-tasklet-triage-ask-tags)
    ;; tags 是整理流程的核心信息，但仍使用 Org 自带的标签编辑体验。
    (call-interactively #'org-set-tags-command)))

(defun org-tasklet--set-current-todo-semantics (semantic)
  "按 SEMANTIC 调整当前标题 TODO 状态。"
  (org-back-to-heading t)
  (let ((org-inhibit-logging 'note))
    (pcase semantic
      ('todo
       (unless (string= (org-get-todo-state) "TODO")
         (org-todo "TODO")))
      ('done
       (unless (string= (org-get-todo-state) "DONE")
         (org-todo "DONE")))
      ('cancel
       (unless (string= (org-get-todo-state) "CNCL")
         (org-todo "CNCL")))
      ('none
       (when (org-get-todo-state)
         (org-todo "")))
      (_ nil))))

(defun org-tasklet--current-subtree-text ()
  "返回当前 Org 子树文本。"
  (org-back-to-heading t)
  (buffer-substring-no-properties
   (point)
   (save-excursion (org-end-of-subtree t t))))

(defun org-tasklet--delete-current-subtree ()
  "删除当前 Org 子树。"
  (org-back-to-heading t)
  (delete-region (point)
                 (save-excursion (org-end-of-subtree t t))))

(defun org-tasklet--subtree-first-level (text)
  "返回 TEXT 中第一个标题的层级。"
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (if (re-search-forward "^\\(\\*+\\)\\(?:[ \t]\\|$\\)" nil t)
        (length (match-string 1))
      1)))

(defun org-tasklet--subtree-at-level (text target-level)
  "把 TEXT 的根标题调整到 TARGET-LEVEL 层级。"
  (let* ((first-level (org-tasklet--subtree-first-level text))
         (delta (- target-level first-level)))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (re-search-forward "^\\(\\*+\\)\\([ \t]\\|$\\)" nil t)
        (let* ((stars (match-string 1))
               (new-level (max 1 (+ (length stars) delta))))
          (replace-match (make-string new-level ?*) nil nil nil 1)))
      (buffer-string))))

(defun org-tasklet--type-heading-names (type)
  "返回 TYPE 可用的顶层标题名列表。"
  (let* ((plist (org-tasklet--organize-entry-plist type))
         (heading (plist-get plist :heading))
         (aliases (plist-get plist :aliases)))
    (delq nil (append (list heading) aliases))))

(defun org-tasklet--goto-top-level-heading (names)
  "移动到第一个匹配 NAMES 的顶层标题；找到时返回标题名。"
  (let ((found nil))
    (goto-char (point-min))
    (while (and (not found)
                (re-search-forward "^\\*\\(?:[ \t]+\\|$\\)" nil t))
      (org-back-to-heading t)
      (let ((title (org-get-heading t t t t)))
        (when (member title names)
          (setq found title)))
      (unless found
        ;; 没找到时必须离开当前标题行，否则下一轮会重复匹配同一个顶层标题。
        (forward-line 1)))
    found))

(defun org-tasklet--goto-or-create-type-heading (type)
  "移动到 TYPE 对应的顶层分类标题；不存在时创建。"
  (let* ((names (org-tasklet--type-heading-names type))
         (heading (car names)))
    (unless heading
      (user-error "分类 %s 没有配置目标标题" type))
    (unless (org-tasklet--goto-top-level-heading names)
      (goto-char (point-max))
      (unless (bolp)
        (insert "\n"))
      (insert "* " heading "\n")
      (forward-line -1)
      (org-back-to-heading t))
    (point-marker)))

(defun org-tasklet--insert-under-current-heading (text)
  "把 TEXT 插入到当前标题的子树末尾，并返回新标题 marker。"
  (org-back-to-heading t)
  (let* ((target-level (1+ (org-outline-level)))
         (adjusted (org-tasklet--subtree-at-level text target-level))
         marker)
    (org-end-of-subtree t t)
    (unless (bolp)
      (insert "\n"))
    (setq marker (point-marker))
    (insert adjusted)
    (unless (bolp)
      (insert "\n"))
    marker))

(defun org-tasklet--insert-subtree-into-type (type text)
  "把 TEXT 插入 tasks 文件的 TYPE 分类下，并返回新标题 marker。"
  (org-tasklet--ensure-file (org-tasklet-tasks-file) "Tasks")
  (with-current-buffer (find-file-noselect (org-tasklet-tasks-file))
    (org-mode)
    (org-with-wide-buffer
     (goto-char (point-min))
     (let ((heading-marker (org-tasklet--goto-or-create-type-heading type)))
       (goto-char heading-marker)
       (let ((new-marker (org-tasklet--insert-under-current-heading text)))
         (save-buffer)
         new-marker)))))

(defun org-tasklet--project-heading-marker ()
  "返回 Projects 顶层标题 marker。"
  (org-tasklet--goto-or-create-type-heading 'project))

(defun org-tasklet--project-candidates ()
  "返回 tasks 文件中可追加任务的项目候选。"
  (org-tasklet--ensure-file (org-tasklet-tasks-file) "Tasks")
  (with-current-buffer (find-file-noselect (org-tasklet-tasks-file))
    (org-mode)
    (org-with-wide-buffer
     (goto-char (point-min))
     (let* ((projects-marker (org-tasklet--project-heading-marker))
            (projects-level (org-with-point-at projects-marker
                              (org-outline-level)))
            (end (save-excursion
                   (goto-char projects-marker)
                   (org-end-of-subtree t t)))
            candidates)
       (goto-char projects-marker)
       (forward-line 1)
       (while (re-search-forward org-heading-regexp end t)
         (when (= (org-outline-level) (1+ projects-level))
           (let* ((title (org-get-heading t t t t))
                  (line (line-number-at-pos))
                  (label (format "%s  (line %d)" title line)))
             (push (cons label (point-marker)) candidates))))
       (nreverse candidates)))))

(defun org-tasklet--read-project-marker ()
  "交互选择一个现有项目，并返回它的 marker。"
  (let* ((candidates (org-tasklet--project-candidates)))
    (unless candidates
      (user-error "tasks 文件的 Projects 分类下还没有项目"))
    (cdr (assoc (completing-read "加入项目: "
                                  (mapcar #'car candidates)
                                  nil t)
                candidates))))

(defun org-tasklet--insert-subtree-into-project (project-marker text)
  "把 TEXT 插入 PROJECT-MARKER 指向的项目下，并返回新标题 marker。"
  (unless (and (markerp project-marker)
               (marker-buffer project-marker))
    (user-error "无效的项目位置"))
  (with-current-buffer (marker-buffer project-marker)
    (org-mode)
    (org-with-wide-buffer
     (goto-char project-marker)
     (org-back-to-heading t)
     (let ((new-marker (org-tasklet--insert-under-current-heading text)))
       (save-buffer)
       new-marker))))

(defun org-tasklet--ensure-direct-children-todo ()
  "确保当前项目的直接子标题拥有 TODO 状态。"
  (org-back-to-heading t)
  (let ((level (org-outline-level))
        (end (save-excursion (org-end-of-subtree t t)))
        (org-inhibit-logging 'note))
    (forward-line 1)
    (while (re-search-forward org-heading-regexp end t)
      (when (and (= (org-outline-level) (1+ level))
                 (not (org-get-todo-state)))
        (org-todo "TODO")))))

(defun org-tasklet--normalize-project-at-marker (project-marker)
  "按项目状态流整理 PROJECT-MARKER 指向的项目。"
  (when (and (markerp project-marker)
             (marker-buffer project-marker))
    (with-current-buffer (marker-buffer project-marker)
      (org-with-wide-buffer
       (goto-char project-marker)
       (org-back-to-heading t)
       (let ((project-pos (point)))
         ;; 项目根标题只表达结果，具体推进状态由直接子任务承担。
         (org-tasklet--set-current-todo-semantics 'none)
         (goto-char project-pos)
         (org-tasklet--ensure-direct-children-todo)
         (goto-char project-pos)
         (org-tasklet-refresh-project)
         (save-buffer))))))

(defun org-tasklet--prepare-current-item-for-type (type)
  "按 TYPE 的分类语义整理当前 inbox 标题。"
  (let* ((plist (org-tasklet--organize-entry-plist type))
         (todo (plist-get plist :todo)))
    (org-tasklet--set-current-todo-semantics todo)
    (when (plist-get plist :style-habit)
      ;; org-habit 使用 STYLE=habit，这是 Org 原生约定，不是 org-gtd 元数据。
      (org-set-property "STYLE" "habit"))))

(defun org-tasklet--archive-current-item-after-type (type)
  "按 TYPE 处理当前条目后归档。"
  (org-tasklet--prepare-current-item-for-type type)
  (org-tasklet-archive-subtree)
  (save-buffer)
  (org-tasklet--refresh-mode-line-if-present)
  (message "已处理并归档为 %s"
           (plist-get (org-tasklet--organize-entry-plist type) :label)))

(defun org-tasklet--move-current-item-to-type (type)
  "按 TYPE 处理当前条目，并移动到对应 tasks 分类。"
  (org-tasklet--prepare-current-item-for-type type)
  (let ((text (org-tasklet--current-subtree-text)))
    (org-tasklet--delete-current-subtree)
    (save-buffer)
    (let ((new-marker (org-tasklet--insert-subtree-into-type type text)))
      (when (eq type 'project)
        (org-tasklet--normalize-project-at-marker new-marker))))
  (org-tasklet--refresh-mode-line-if-present)
  (message "已整理到 %s"
           (plist-get (org-tasklet--organize-entry-plist type) :heading)))

(defun org-tasklet--move-current-item-to-project (project-marker)
  "把当前 inbox item 追加到 PROJECT-MARKER 指向的项目中。"
  (org-tasklet--prepare-current-item-for-type 'project-task)
  (let ((text (org-tasklet--current-subtree-text)))
    (org-tasklet--delete-current-subtree)
    (save-buffer)
    (org-tasklet--insert-subtree-into-project project-marker text)
    (org-tasklet--normalize-project-at-marker project-marker))
  (org-tasklet--refresh-mode-line-if-present)
  (message "已加入项目"))

(defun org-tasklet--triage-one-item (type tags project-marker interactivep)
  "按分类整理当前 inbox item 的一次性处理核心。

TYPE 为 nil 时交互选择分类；TAGS 非 nil 时直接设置 tags；
PROJECT-MARKER 用于非交互地指定 Add to Project 的目标项目；
INTERACTIVEP 非 nil 时使用 Org 自带 tags 编辑命令。"
  (org-tasklet--ensure-current-inbox-item)
  (let ((selected-type (or (org-tasklet--normalize-organize-type type)
                           (org-tasklet--read-organize-type))))
    (org-tasklet--organize-entry selected-type)
    (org-tasklet--apply-current-tags tags interactivep)
    (pcase selected-type
      ('project-task
       (org-tasklet--move-current-item-to-project
        (or project-marker
            (org-tasklet--read-project-marker))))
      ((guard (plist-get (org-tasklet--organize-entry-plist selected-type)
                         :archive))
       (org-tasklet--archive-current-item-after-type selected-type))
      (_
       (org-tasklet--move-current-item-to-type selected-type)))))

(defun org-tasklet--goto-next-inbox-item (&optional pos)
  "把光标定位到 POS（默认当前位置）之后最近的条目标题。

光标已在标题行时停在该标题。找到时返回 point，否则返回 nil。"
  (goto-char (or pos (point)))
  (beginning-of-line)
  (cond
   ((org-at-heading-p) (point))
   ((re-search-forward org-heading-regexp nil t)
    (org-back-to-heading t)
    (point))
   (t nil)))

(defun org-tasklet-triage-items ()
  "从当前 item 开始连续整理 inbox 条目。

当前 buffer 不是 inbox 时，先打开 inbox 并跳到第一个 item。
每处理完一个 item 自动激活下一个，处理完末尾后回到开头补漏，
直到全部处理完；C-g 随时退出。"
  (interactive)
  (if (org-tasklet-inbox-buffer-p)
      ;; 光标在某个条目正文里时，从该条目开始处理。
      (unless (org-before-first-heading-p)
        (org-back-to-heading t))
    (find-file (org-tasklet--ensure-file (org-tasklet-inbox-file) "Inbox"))
    (org-mode)
    (org-tasklet--show-all)
    (goto-char (point-min)))
  (let ((processed 0))
    (condition-case nil
        (progn
          (while (or (org-tasklet--goto-next-inbox-item)
                     ;; 从中间条目开始时，处理完末尾后回到开头补漏。
                     (org-tasklet--goto-next-inbox-item (point-min)))
            (let ((resume (copy-marker (point))))
              ;; 整理会删除当前子树；marker 随后正好落在下一个条目开头。
              (unwind-protect
                  (org-tasklet--triage-one-item nil nil nil t)
                (goto-char resume)
                (set-marker resume nil)))
            (setq processed (1+ processed)))
          (message "inbox 整理完成，共处理 %d 个 item" processed))
      (quit
       (message "已退出 inbox 整理，共处理 %d 个 item" processed)))))

(defun org-tasklet-triage-current-item (&optional type tags project-marker)
  "按分类整理当前 inbox item。

交互调用时进入连续整理：当前 buffer 不是 inbox 会先打开 inbox 并跳到
第一个 item；每处理完一个自动激活下一个，直到全部处理完或 C-g 退出。
Lisp 调用时只处理当前 item：TYPE 为 nil 时交互选择分类；TAGS 非 nil
时直接设置 tags；PROJECT-MARKER 用于非交互地指定 Add to Project 的目
标项目。"
  (interactive)
  (let ((interactivep (called-interactively-p 'interactive)))
    (if (and interactivep (not (or type tags project-marker)))
        (org-tasklet-triage-items)
      (org-tasklet--triage-one-item type tags project-marker interactivep))))

(defun org-tasklet-triage-move-to-tasks ()
  "把当前 inbox 条目作为 Action 移动到 tasks 文件。"
  (interactive)
  (org-tasklet-triage-current-item 'action))

(defun org-tasklet-triage-done ()
  "把当前 inbox 条目标记为 DONE。"
  (interactive)
  (org-tasklet--ensure-current-inbox-item)
  (org-tasklet--set-current-todo-semantics 'done)
  (save-buffer)
  (org-tasklet--refresh-mode-line-if-present))

(defun org-tasklet-triage-cancel ()
  "把当前 inbox 条目标记为 CNCL。"
  (interactive)
  (org-tasklet--ensure-current-inbox-item)
  (org-tasklet--set-current-todo-semantics 'cancel)
  (save-buffer)
  (org-tasklet--refresh-mode-line-if-present))

(defun org-tasklet-triage-make-project ()
  "把当前 inbox 条目作为新项目移动到 tasks。"
  (interactive)
  (org-tasklet-triage-current-item 'project))

(provide 'org-tasklet-triage)

;;; org-tasklet-triage.el 到此结束
