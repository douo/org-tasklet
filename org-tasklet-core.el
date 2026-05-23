;;; org-tasklet-core.el --- 核心配置和文件工具 -*- lexical-binding: t; -*-

;; 版权：2026

;; 作者：tiou
;; 版本：0.1.0
;; 依赖包：((emacs "27.1") (org "9.5"))

;;; 说明：
;; 这里放不依赖 Org 解析器的轻量工具，方便入口文件快速加载。

;;; 代码：

(require 'cl-lib)
(require 'subr-x)

(defgroup org-tasklet nil
  "轻量 Org 任务跟踪器。"
  :group 'org
  :prefix "org-tasklet-")

(defcustom org-tasklet-directory (expand-file-name "~/org-tasklet")
  "任务数据目录。"
  :type 'directory
  :group 'org-tasklet)

(defcustom org-tasklet-inbox-file-name "inbox.org"
  "收件箱文件名。"
  :type 'string
  :group 'org-tasklet)

(defcustom org-tasklet-tasks-file-name "tasks.org"
  "正式任务文件名。"
  :type 'string
  :group 'org-tasklet)

(defcustom org-tasklet-archive-directory-name ".archive"
  "归档目录名。"
  :type 'string
  :group 'org-tasklet)

(defcustom org-tasklet-archive-file-format "todo_%Y.org"
  "年度归档文件名格式。"
  :type 'string
  :group 'org-tasklet)

(defcustom org-tasklet-project-property "TASKLET_PROJECT"
  "标记项目标题的 Org 属性名。"
  :type 'string
  :group 'org-tasklet)

(defcustom org-tasklet-read-later-tag "read"
  "浏览器稍后阅读捕获使用的标签。"
  :type 'string
  :group 'org-tasklet)

(defcustom org-tasklet-todo-keywords '("TODO" "NEXT" "|" "DONE" "CNCL")
  "插件使用的 TODO 状态序列。"
  :type '(repeat string)
  :group 'org-tasklet)

(defcustom org-tasklet-open-keywords '("TODO" "NEXT")
  "表示未完成任务的状态。"
  :type '(repeat string)
  :group 'org-tasklet)

(defcustom org-tasklet-closed-keywords '("DONE" "CNCL")
  "表示已关闭任务的状态。"
  :type '(repeat string)
  :group 'org-tasklet)

(defcustom org-tasklet-mode-line-display 'when-non-zero
  "mode-line 收件箱计数的显示策略。"
  :type '(choice (const :tag "始终显示" t)
                 (const :tag "非零时显示" when-non-zero)
                 (const :tag "不显示" nil))
  :group 'org-tasklet)

(defcustom org-tasklet-mode-line-refresh-interval nil
  "mode-line 收件箱计数的自动刷新间隔；nil 表示不启用定时器。"
  :type '(choice (const :tag "关闭" nil)
                 (integer :tag "秒数"))
  :group 'org-tasklet)

(defcustom org-tasklet-organize-types
  '((action
     :label "Action"
     :heading "Actions"
     :todo todo)
    (project
     :label "Project"
     :heading "Projects"
     :todo none)
    (project-task
     :label "Add to Project"
     :heading "Projects"
     :todo todo)
    (calendar
     :label "Calendar"
     :heading "Calendar"
     :todo todo)
    (habit
     :label "Habit"
     :heading "Habits"
     :todo todo
     :style-habit t)
    (tickler
     :label "Tickler"
     :heading "Tickler"
     :todo none)
    (incubate
     :label "Incubate"
     :heading "Incubate"
     :aliases ("Someday" "Someday/Maybe")
     :todo none)
    (reference
     :label "Reference"
     :heading "Reference"
     :todo none)
    (quick
     :label "Quick Action"
     :todo done
     :archive t)
    (trash
     :label "Trash"
     :todo cancel
     :archive t))
  "inbox 整理分类表。

每个分类可以定义这些字段：

- :label 交互选择时显示的名字。
- :heading 移动到 tasks 文件里的顶层标题。
- :aliases 查找已有顶层标题时接受的别名。
- :todo 对当前标题应用的状态语义：todo、done、cancel 或 none。
- :style-habit 非 nil 时设置 Org 原生 STYLE=habit 属性。
- :archive 非 nil 时处理后直接归档，而不是移动到 tasks。"
  :type 'sexp
  :group 'org-tasklet)

(defcustom org-tasklet-protocols '("tasklet-capture")
  "注册给 org-protocol 的新协议名列表。"
  :type '(repeat string)
  :group 'org-tasklet)

(defcustom org-tasklet-legacy-protocols '("gtd-capture")
  "为了兼容旧浏览器脚本而保留的 org-protocol 协议名列表。"
  :type '(repeat string)
  :group 'org-tasklet)

(defun org-tasklet--directory ()
  "返回规范化后的任务目录。"
  (file-name-as-directory (expand-file-name org-tasklet-directory)))

(defun org-tasklet--file (file-name)
  "返回任务目录下 FILE-NAME 的完整路径。"
  (expand-file-name file-name (org-tasklet--directory)))

(defun org-tasklet--same-file-p (file-a file-b)
  "判断 FILE-A 和 FILE-B 是否指向同一个文件。"
  (when (and file-a file-b)
    (let ((expanded-a (expand-file-name file-a))
          (expanded-b (expand-file-name file-b)))
      ;; 先做字符串比较，避免不存在的文件触发真实路径判断失败。
      (or (string= expanded-a expanded-b)
          (and (file-exists-p expanded-a)
               (file-exists-p expanded-b)
               (file-equal-p expanded-a expanded-b))))))

(defun org-tasklet-inbox-file ()
  "返回收件箱文件路径。"
  (org-tasklet--file org-tasklet-inbox-file-name))

(defun org-tasklet-inbox-buffer-p (&optional buffer)
  "判断 BUFFER 是否正在访问 Tasklet 收件箱文件。"
  (with-current-buffer (or buffer (current-buffer))
    (org-tasklet--same-file-p (buffer-file-name) (org-tasklet-inbox-file))))

(defun org-tasklet-tasks-file ()
  "返回正式任务文件路径。"
  (org-tasklet--file org-tasklet-tasks-file-name))

(defun org-tasklet-archive-directory ()
  "返回归档目录路径。"
  (org-tasklet--file org-tasklet-archive-directory-name))

(defun org-tasklet-archive-file (&optional time)
  "返回 TIME 所在年份的归档文件路径。"
  (expand-file-name
   (format-time-string org-tasklet-archive-file-format time)
   (org-tasklet-archive-directory)))

(defun org-tasklet-archive-location (&optional time)
  "返回适合 `org-archive-location' 使用的年度 datetree 位置。"
  (concat (org-tasklet-archive-file time) "::datetree/"))

(defun org-tasklet--todo-keyword-line ()
  "生成写入 Org 文件头部的 TODO 状态行。"
  (concat "#+TODO: " (string-join org-tasklet-todo-keywords " ") "\n"))

(defun org-tasklet--file-header (title)
  "生成 TITLE 对应的新文件头部。"
  (concat "#+TITLE: " title "\n"
          (org-tasklet--todo-keyword-line)
          "\n"))

(defun org-tasklet--ensure-directory ()
  "确保任务目录和归档目录存在。"
  (make-directory (org-tasklet--directory) t)
  (make-directory (org-tasklet-archive-directory) t))

(defun org-tasklet--ensure-file (file title)
  "确保 FILE 存在；新建时写入 TITLE 和 TODO 状态。"
  (org-tasklet--ensure-directory)
  (unless (file-exists-p file)
    (with-temp-buffer
      (insert (org-tasklet--file-header title))
      (write-region (point-min) (point-max) file nil 'silent)))
  file)

(defun org-tasklet-ensure-files ()
  "确保插件需要的基础文件存在。"
  (list (org-tasklet--ensure-file (org-tasklet-inbox-file) "Inbox")
        (org-tasklet--ensure-file (org-tasklet-tasks-file) "Tasks")))

(defun org-tasklet--read-file-string (file)
  "读取 FILE 的文本内容；文件不存在时返回空字符串。"
  (if (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string))
    ""))

(defun org-tasklet-count-open-headlines (file &optional keywords)
  "统计 FILE 中处于 KEYWORDS 状态的标题数量。"
  (let* ((states (or keywords org-tasklet-open-keywords))
         (regexp (format "^\\*+ \\(%s\\)\\(?:[ \t]\\|$\\)"
                         (regexp-opt states)))
         (count 0))
    (with-temp-buffer
      (insert (org-tasklet--read-file-string file))
      (goto-char (point-min))
      (while (re-search-forward regexp nil t)
        (setq count (1+ count))))
    count))

(defun org-tasklet-count-unclosed-headlines (file)
  "统计 FILE 中未关闭的标题数量，包含没有 TODO 关键字的标题。"
  (let ((closed-regexp
         (format "\\`\\(?:%s\\)\\(?:[ \t]\\|\\'\\)"
                 (regexp-opt org-tasklet-closed-keywords)))
        (count 0))
    (with-temp-buffer
      (insert (org-tasklet--read-file-string file))
      (goto-char (point-min))
      (while (re-search-forward "^\\*+ \\(.*\\)$" nil t)
        (unless (string-match-p closed-regexp (match-string 1))
          (setq count (1+ count)))))
    count))

(defun org-tasklet-inbox-count ()
  "统计收件箱中未完成条目的数量。"
  (org-tasklet-count-unclosed-headlines (org-tasklet-inbox-file)))

(defun org-tasklet--clean-title (title)
  "清理 TITLE，让它适合作为单行 Org 标题。"
  (let ((cleaned (string-trim
                  (replace-regexp-in-string "[\n\r\t]+" " " (or title "")))))
    (if (string-empty-p cleaned)
        "未命名任务"
      cleaned)))

(defun org-tasklet--inactive-timestamp (&optional time)
  "返回 TIME 对应的非活跃时间戳。"
  (format-time-string "[%Y-%m-%d %a %H:%M]" time))

(defun org-tasklet--append-to-file (file text title)
  "把 TEXT 追加到 FILE；文件不存在时用 TITLE 初始化。"
  (org-tasklet--ensure-file file title)
  (with-temp-buffer
    (insert text)
    (unless (bolp)
      (insert "\n"))
    (append-to-file (point-min) (point-max) file)))

(defun org-tasklet--refresh-mode-line-if-present ()
  "如果 mode-line 功能已经加载，则刷新收件箱计数。"
  (when (fboundp 'org-tasklet-refresh-mode-line)
    (org-tasklet-refresh-mode-line)))

(provide 'org-tasklet-core)

;;; org-tasklet-core.el 到此结束
