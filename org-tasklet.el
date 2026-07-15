;;; org-tasklet.el --- 轻量 Org 任务跟踪器入口 -*- lexical-binding: t; -*-

;; 版权：2026

;; 作者：tiou
;; 版本：0.1.0
;; 依赖包：((emacs "27.1") (org "9.5"))

;;; 说明：
;; 入口文件只加载轻量核心和 mode-line 逻辑，其他功能通过 autoload 延迟加载。

;;; 代码：

(require 'org-tasklet-core)

(defvar org-tasklet--mode-line-string ""
  "mode-line 中显示的收件箱计数字符串。")

(defvar org-tasklet--mode-line-timer nil
  "刷新 mode-line 收件箱计数的定时器。")

(defconst org-tasklet-help-text
  "org-tasklet 帮助
================

定位
----

org-tasklet 是轻量 Org todo list 跟踪插件。它保留 inbox、tasks、
项目状态流、agenda、归档、浏览器稍后阅读和 mode-line inbox 数量，
但不维护 org-gtd 的属性数据库、DAG 或线性 Process 流程。

常用命令
--------

M-x org-tasklet-capture
  使用 Tasklet 捕获模板。

M-x org-tasklet-triage
  打开 inbox.org。

M-x org-tasklet-triage-current-item
  在当前 inbox item 上选择分类并整理。交互调用会进入连续整理：
  不在 inbox 时先打开 inbox 并跳到第一个 item，处理完一个自动激活
  下一个，直到全部完成或 C-g 退出。

M-x org-tasklet-engage
  打开 agenda 总览。

M-x org-tasklet-show-next
  查看项目下一步。

M-x org-tasklet-refresh-project
  刷新当前项目的 NEXT 状态。

M-x org-tasklet-archive-done
  归档 DONE 和 CNCL 条目。

inbox 分类
----------

Action
  单步任务。移动到 tasks.org 的 Actions，并保持 TODO。

Project
  多步项目。移动到 Projects。项目根标题不强制 TODO，直接子任务使用
  TODO/NEXT 状态流。

Add to Project
  把当前 inbox item 追加到已有项目下，并刷新该项目的 NEXT。

Calendar
  需要出现在 agenda 的任务。移动到 Calendar。SCHEDULED、DEADLINE 和
  时间戳直接用 Org 文本编辑，不需要专门的整理动作。

Habit
  定期习惯。移动到 Habits，并使用 Org 原生 STYLE: habit。

Tickler
  有明确提醒时间、以后再看的任务。移动到 Tickler。

Incubate
  没有明确时间承诺的以后可能事项。移动到 Incubate。

Reference
  参考资料。移动到 Reference。

Quick Action
  已经立即完成的条目。标记 DONE 后归档。

Trash
  不需要的条目。标记 CNCL 后归档。

注意事项
--------

- tags 是整理流程的一部分；交互调用时使用 Org 自带 tags 编辑命令。
- 整理过程不写 ORG_GTD、ORG_GTD_REFILE、ORG_GTD_PROJECT_IDS 等 org-gtd 元数据。
- 日期、排期、截止日期、priority 和 effort 保持普通 Org 文本编辑。
- 不要用 emacsclient 验证此插件，避免影响正在运行的 Emacs 进程。

预编译
------

为了避免第一次打开新功能时临时编译卡顿，可以在插件目录执行：

  make compile

如果 Emacs 支持 native-comp，也可以提前生成原生编译缓存：

  make native-compile

建议流程：

  make test
  make compile
  make native-compile

注意：

- 预编译只处理插件文件，不连接或影响正在运行的 Emacs 进程。
- 修改任意 *.el 后，建议重新运行 make compile 或 make native-compile。
- 升级 Emacs、大版本切换或清理 eln-cache 后，需要重新 native compile。
"
  "org-tasklet 内置帮助文本。")

(defun org-tasklet-refresh-mode-line ()
  "刷新 mode-line 中的收件箱计数。"
  (interactive)
  (let ((count (org-tasklet-inbox-count)))
    (setq org-tasklet--mode-line-string
          (pcase org-tasklet-mode-line-display
            ('nil "")
            ('when-non-zero (if (> count 0) (format " Tasklet[%d]" count) ""))
            (_ (format " Tasklet[%d]" count))))
    (force-mode-line-update t)
    count))

(defun org-tasklet--enable-mode-line ()
  "启用 mode-line 收件箱计数。"
  (unless (memq 'org-tasklet--mode-line-string global-mode-string)
    (setq global-mode-string
          (append global-mode-string '(org-tasklet--mode-line-string))))
  (org-tasklet-refresh-mode-line)
  (when org-tasklet-mode-line-refresh-interval
    (setq org-tasklet--mode-line-timer
          (run-at-time t org-tasklet-mode-line-refresh-interval
                       #'org-tasklet-refresh-mode-line))))

(defun org-tasklet--disable-mode-line ()
  "关闭 mode-line 收件箱计数。"
  (setq global-mode-string
        (delq 'org-tasklet--mode-line-string global-mode-string))
  (when (timerp org-tasklet--mode-line-timer)
    (cancel-timer org-tasklet--mode-line-timer))
  (setq org-tasklet--mode-line-timer nil
        org-tasklet--mode-line-string "")
  (force-mode-line-update t))

(define-minor-mode org-tasklet-mode
  "显示轻量任务系统的全局状态。"
  :global t
  :group 'org-tasklet
  :lighter nil
  (if org-tasklet-mode
      (org-tasklet--enable-mode-line)
    (org-tasklet--disable-mode-line)))

(defun org-tasklet-setup ()
  "创建基础文件，并把任务目录加入 Org agenda。"
  (interactive)
  (org-tasklet-ensure-files)
  (with-eval-after-load 'org
    (defvar org-todo-keywords)
    (add-to-list 'org-todo-keywords `(sequence ,@org-tasklet-todo-keywords) t))
  (with-eval-after-load 'org-agenda
    (defvar org-agenda-files)
    (add-to-list 'org-agenda-files (org-tasklet--directory) t))
  (message "org-tasklet 已准备好：%s" (org-tasklet--directory)))

(defun org-tasklet-help ()
  "显示 org-tasklet 的使用帮助和预编译说明。"
  (interactive)
  (with-help-window "*Org Tasklet Help*"
    (princ org-tasklet-help-text)))

(autoload 'org-tasklet-capture-inbox "org-tasklet-capture" nil t)
(autoload 'org-tasklet-capture "org-tasklet-capture" nil t)
(autoload 'org-tasklet-capture-read-later "org-tasklet-capture" nil t)
(autoload 'org-tasklet-capture-inbox-file "org-tasklet-capture" nil nil)
(autoload 'org-tasklet-open-inbox "org-tasklet-capture" nil t)
(autoload 'org-tasklet-open-tasks "org-tasklet-capture" nil t)
(autoload 'org-tasklet-engage "org-tasklet-agenda" nil t)
(autoload 'org-tasklet-show-next "org-tasklet-agenda" nil t)
(autoload 'org-tasklet-agenda-todo-dwim "org-tasklet-agenda" nil t)
(autoload 'org-tasklet-triage "org-tasklet-triage" nil t)
(autoload 'org-tasklet-triage-current-item "org-tasklet-triage" nil t)
(autoload 'org-tasklet-triage-items "org-tasklet-triage" nil t)
(autoload 'org-tasklet-archive-done "org-tasklet-archive" nil t)
(autoload 'org-tasklet-archive-subtree "org-tasklet-archive" nil t)
(autoload 'org-tasklet-register-org-protocol "org-tasklet-protocol" nil t)
(autoload 'org-tasklet-mark-project "org-tasklet-project" nil t)
(autoload 'org-tasklet-refresh-project "org-tasklet-project" nil t)
(autoload 'org-tasklet-refresh-all-projects "org-tasklet-project" nil t)
(autoload 'org-tasklet-reflect-stuck-projects "org-tasklet-project" nil t)
(autoload 'org-tasklet-project-done-and-advance "org-tasklet-project" nil t)

(provide 'org-tasklet)

;;; org-tasklet.el 到此结束
