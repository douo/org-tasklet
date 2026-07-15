;;; org-tasklet-test.el --- org-tasklet 测试 -*- lexical-binding: t; -*-

;;; 代码：

(require 'ert)
(require 'org-tasklet)
(require 'org-tasklet-capture)
(require 'org-tasklet-project)
(require 'org-tasklet-archive)
(require 'org-tasklet-protocol)
(require 'org-tasklet-triage)

(defmacro org-tasklet-test--with-temp-dir (&rest body)
  "在临时任务目录中执行 BODY。"
  (declare (indent 0) (debug t))
  `(let ((org-tasklet-directory (make-temp-file "org-tasklet-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory org-tasklet-directory t))))

(ert-deftest org-tasklet-ensure-files-creates-basic-files ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (should (file-exists-p (org-tasklet-inbox-file)))
    (should (file-exists-p (org-tasklet-tasks-file)))
    (should (string-match-p "#\\+TODO: TODO NEXT | DONE CNCL"
                            (org-tasklet--read-file-string
                             (org-tasklet-inbox-file))))))

(ert-deftest org-tasklet-capture-read-later-writes-inbox ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-capture-read-later "https://example.com/a" "Example" "Body")
    (let ((text (org-tasklet--read-file-string (org-tasklet-inbox-file))))
      (should (string-match-p "\\* TODO \\[\\[https://example.com/a\\]\\[Example\\]\\] :read:" text))
      (should (string-match-p "Body" text))
      (should (= 1 (org-tasklet-inbox-count))))))

(ert-deftest org-tasklet-inbox-count-includes-plain-headings ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-temp-file (org-tasklet-inbox-file)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* Plain inbox item\n"
              "* TODO Todo inbox item\n"
              "* DONE Closed inbox item\n"))
    (should (= 2 (org-tasklet-inbox-count)))))

(ert-deftest org-tasklet-triage-current-item-moves-current-heading ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-temp-file (org-tasklet-tasks-file)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* Actions\n"))
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                    "* TODO Keep\n"
                    "* TODO Move me\n"
                    "Body\n"
                    "* TODO Also keep\n")
            (org-mode)
            (goto-char (point-min))
            (re-search-forward "Body")
            (org-tasklet-triage-current-item 'move)
            (should-not (string-match-p "Move me"
                                        (org-tasklet--read-file-string
                                         (org-tasklet-inbox-file))))
            (should (string-match-p "\\* TODO Keep"
                                    (org-tasklet--read-file-string
                                     (org-tasklet-inbox-file))))
            (should (string-match-p "\\* TODO Also keep"
                                    (org-tasklet--read-file-string
                                     (org-tasklet-inbox-file))))
            (should (string-match-p "\\* Actions\n\\*\\* TODO Move me"
                                    (org-tasklet--read-file-string
                                     (org-tasklet-tasks-file)))))
        (kill-buffer)))))

(ert-deftest org-tasklet-triage-current-item-keeps-tags-and-skips-org-gtd-metadata ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                    "* TODO Tag me\n")
            (org-mode)
            (goto-char (point-min))
            (re-search-forward "Tag me")
            (org-tasklet-triage-current-item 'action '("work" "ai")))
        (kill-buffer)))
    (let ((text (org-tasklet--read-file-string (org-tasklet-tasks-file))))
      (should (string-match-p "\\*\\* TODO Tag me[ \t]+:@?work:ai:\\|\\*\\* TODO Tag me[ \t]+:work:ai:" text))
      (should-not (string-match-p "ORG_GTD" text)))))

(ert-deftest org-tasklet-triage-current-item-requires-inbox-heading ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n")
            (org-mode)
            (goto-char (point-min))
            (should-error (org-tasklet-triage-current-item 'done)
                          :type 'user-error))
        (kill-buffer)))
    (let ((other-file (expand-file-name "other.org" org-tasklet-directory)))
      (with-temp-file other-file
        (insert "* TODO Other\n"))
      (with-current-buffer (find-file-noselect other-file)
        (unwind-protect
            (progn
              (org-mode)
              (goto-char (point-min))
              (re-search-forward "Other")
              (should-error (org-tasklet-triage-current-item 'done)
                            :type 'user-error))
          (kill-buffer))))))

(ert-deftest org-tasklet-triage-opens-inbox-file ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (kill-buffer))
    (unwind-protect
        (progn
          (org-tasklet-triage)
          (should (org-tasklet-inbox-buffer-p)))
      (when (get-file-buffer (org-tasklet-inbox-file))
        (kill-buffer (get-file-buffer (org-tasklet-inbox-file)))))))

(ert-deftest org-tasklet-inbox-buffer-p-ignores-other-files ()
  (org-tasklet-test--with-temp-dir
    (let ((other-file (expand-file-name "other.org" org-tasklet-directory)))
      (org-tasklet-ensure-files)
      (with-temp-file other-file
        (insert "* TODO Other\n"))
      (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
        (unwind-protect
            (progn
              (org-mode)
              (should (org-tasklet-inbox-buffer-p)))
          (kill-buffer)))
      (with-current-buffer (find-file-noselect other-file)
        (unwind-protect
            (progn
              (org-mode)
              (should-not (org-tasklet-inbox-buffer-p)))
          (kill-buffer))))))

(ert-deftest org-tasklet-project-refresh-promotes-first-child ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-tasks-file))
      (erase-buffer)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* TODO Project\n"
              ":PROPERTIES:\n"
              ":TASKLET_PROJECT: t\n"
              ":END:\n"
              "** TODO First\n"
              "** TODO Second\n")
      (org-mode)
      (goto-char (point-min))
      (re-search-forward "^\\* TODO Project")
      (org-tasklet-refresh-project)
      (goto-char (point-min))
      (should (re-search-forward "^\\*\\* NEXT First" nil t))
      (should (re-search-forward "^\\*\\* TODO Second" nil t)))))

(ert-deftest org-tasklet-stuck-projects-finds-project-without-next ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-tasks-file))
      (erase-buffer)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* TODO Stuck\n"
              "** TODO First\n"
              "* TODO Moving\n"
              "** NEXT First\n")
      (org-mode)
      (save-buffer))
    (let ((projects (org-tasklet-stuck-projects)))
      (should (= 1 (length projects)))
      (should (string= "Stuck" (plist-get (car projects) :title))))))

(ert-deftest org-tasklet-capture-templates-include-inbox-link-and-read-later ()
  (should (assoc "i" org-tasklet-capture-templates))
  (should (assoc "l" org-tasklet-capture-templates))
  (should (assoc "r" org-tasklet-capture-templates)))

(ert-deftest org-tasklet-help-documents-organize-and-precompile ()
  (should (string-match-p "Add to Project" org-tasklet-help-text))
  (should (string-match-p "ORG_GTD" org-tasklet-help-text))
  (should (string-match-p "make compile" org-tasklet-help-text))
  (should (string-match-p "make native-compile" org-tasklet-help-text))
  (should (string-match-p "不连接或影响正在运行的 Emacs 进程" org-tasklet-help-text)))

(ert-deftest org-tasklet-archive-done-moves-closed-items ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (erase-buffer)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* DONE Finished\n"
              "* TODO Open\n")
      (org-mode)
      (save-buffer))
    (should (= 1 (org-tasklet-archive-done)))
    (should (string-match-p "\\* TODO Open"
                            (org-tasklet--read-file-string
                             (org-tasklet-inbox-file))))
    (should-not (string-match-p "\\* DONE Finished"
                                (org-tasklet--read-file-string
                                 (org-tasklet-inbox-file))))
    (should (string-match-p "Finished"
                            (org-tasklet--read-file-string
                             (org-tasklet-archive-file))))))

(ert-deftest org-tasklet-protocol-keeps-gtd-capture-compatible ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-protocol-capture
     "r/https%3A%2F%2Fexample.com%2Fpage/Example%20Page/Selected%20Text")
    (let ((text (org-tasklet--read-file-string (org-tasklet-inbox-file))))
      (should (string-match-p "Example Page" text))
      (should (string-match-p "Selected Text" text))
      (should (= 1 (org-tasklet-inbox-count))))))

(ert-deftest org-tasklet-triage-move-to-tasks-removes-from-inbox ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (erase-buffer)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* TODO Move me\n"
              "Body\n")
      (org-mode)
      (goto-char (point-min))
      (re-search-forward "^\\* TODO Move me")
      (org-tasklet-triage-move-to-tasks))
    (should-not (string-match-p "Move me"
                                (org-tasklet--read-file-string
                                 (org-tasklet-inbox-file))))
    (should (string-match-p "\\* TODO Move me"
                            (org-tasklet--read-file-string
                             (org-tasklet-tasks-file))))))

(ert-deftest org-tasklet-triage-move-adds-todo-to-plain-heading ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (erase-buffer)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* Plain move\n")
      (org-mode)
      (goto-char (point-min))
      (re-search-forward "^\\* Plain move")
      (org-tasklet-triage-move-to-tasks))
    (should (string-match-p "\\* TODO Plain move"
                            (org-tasklet--read-file-string
                             (org-tasklet-tasks-file))))))

(ert-deftest org-tasklet-triage-project-creates-project-tree ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-temp-file (org-tasklet-tasks-file)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* Projects\n"))
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                    "* TODO New project\n"
                    "** First step\n"
                    "** TODO Second step\n")
            (org-mode)
            (goto-char (point-min))
            (re-search-forward "^\\* TODO New project")
            (org-tasklet-triage-current-item 'project '("ai")))
        (kill-buffer)))
    (let ((text (org-tasklet--read-file-string (org-tasklet-tasks-file))))
      (should (string-match-p "\\* Projects\n\\*\\* New project[ \t]+:ai:" text))
      (should (string-match-p "\\*\\*\\* NEXT First step" text))
      (should (string-match-p "\\*\\*\\* TODO Second step" text))
      (should-not (string-match-p "TASKLET_PROJECT\\|ORG_GTD" text)))))

(ert-deftest org-tasklet-triage-project-task-adds-to-selected-project ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-temp-file (org-tasklet-tasks-file)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* Projects\n"
              "** Existing project\n"
              "*** NEXT Existing step\n"))
    (let (project-marker)
      (with-current-buffer (find-file-noselect (org-tasklet-tasks-file))
        (unwind-protect
            (progn
              (org-mode)
              (goto-char (point-min))
              (re-search-forward "^\\*\\* Existing project")
              (setq project-marker (point-marker)))
          nil))
      (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
        (unwind-protect
            (progn
              (erase-buffer)
              (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                      "* Add this task\n")
              (org-mode)
              (goto-char (point-min))
              (re-search-forward "^\\* Add this task")
              (org-tasklet-triage-current-item 'project-task '("emacs") project-marker))
          (kill-buffer)))
      (when (marker-buffer project-marker)
        (kill-buffer (marker-buffer project-marker))))
    (let ((text (org-tasklet--read-file-string (org-tasklet-tasks-file))))
      (should (string-match-p "\\*\\* Existing project" text))
      (should (string-match-p "\\*\\*\\* NEXT Existing step" text))
      (should (string-match-p "\\*\\*\\* TODO Add this task[ \t]+:emacs:" text))
      (should-not (string-match-p "Add this task"
                                  (org-tasklet--read-file-string
                                   (org-tasklet-inbox-file)))))))

(ert-deftest org-tasklet-triage-calendar-preserves-org-date-text ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                    "* Google One\n"
                    "SCHEDULED: <2026-05-24 Sun>\n")
            (org-mode)
            (goto-char (point-min))
            (re-search-forward "^\\* Google One")
            (org-tasklet-triage-current-item 'calendar))
        (kill-buffer)))
    (let ((text (org-tasklet--read-file-string (org-tasklet-tasks-file))))
      (should (string-match-p "\\* Calendar\n\\*\\* TODO Google One" text))
      (should (string-match-p "SCHEDULED: <2026-05-24 Sun>" text)))))

(ert-deftest org-tasklet-triage-habit-uses-default-heading-and-style ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-temp-file (org-tasklet-tasks-file)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* Habits\n"))
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                    "* Sleep early\n")
            (org-mode)
            (goto-char (point-min))
            (re-search-forward "^\\* Sleep early")
            (org-tasklet-triage-current-item 'habit))
        (kill-buffer)))
    (let ((text (org-tasklet--read-file-string (org-tasklet-tasks-file))))
      (should (string-match-p "\\* Habits\n\\*\\* TODO Sleep early" text))
      (should (string-match-p ":STYLE:[ \t]+habit" text)))))

(ert-deftest org-tasklet-triage-tickler-and-incubate-clear-todo ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                    "* TODO Revisit later\n"
                    "* TODO Maybe someday\n")
            (org-mode)
            (goto-char (point-min))
            (re-search-forward "^\\* TODO Revisit later")
            (org-tasklet-triage-current-item 'tickler)
            (goto-char (point-min))
            (re-search-forward "^\\* TODO Maybe someday")
            (org-tasklet-triage-current-item 'incubate))
        (kill-buffer)))
    (let ((text (org-tasklet--read-file-string (org-tasklet-tasks-file))))
      (should (string-match-p "\\* Tickler\n\\*\\* Revisit later" text))
      (should-not (string-match-p "\\*\\* TODO Revisit later" text))
      (should (string-match-p "\\* Incubate\n\\*\\* Maybe someday" text))
      (should-not (string-match-p "\\*\\* TODO Maybe someday" text)))))

(ert-deftest org-tasklet-triage-quick-and-trash-archive-current-item ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                    "* TODO Two minute task\n"
                    "* TODO No longer needed\n")
            (org-mode)
            (goto-char (point-min))
            (re-search-forward "^\\* TODO Two minute task")
            (org-tasklet-triage-current-item 'quick)
            (goto-char (point-min))
            (re-search-forward "^\\* TODO No longer needed")
            (org-tasklet-triage-current-item 'trash))
        (kill-buffer)))
    (let ((inbox (org-tasklet--read-file-string (org-tasklet-inbox-file)))
          (archive (org-tasklet--read-file-string (org-tasklet-archive-file))))
      (should-not (string-match-p "Two minute task\\|No longer needed" inbox))
      (should (string-match-p "DONE Two minute task" archive))
      (should (string-match-p "CNCL No longer needed" archive)))))

(ert-deftest org-tasklet-triage-items-processes-from-current-and-wraps ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                    "* TODO First\n"
                    "* TODO Second\n"
                    "Body\n"
                    "* TODO Third\n")
            (org-mode)
            (goto-char (point-min))
            ;; 从中间条目开始，验证处理完末尾后回到开头补漏。
            (re-search-forward "Body")
            (let ((org-tasklet-triage-ask-tags nil))
              (cl-letf (((symbol-function 'org-tasklet--read-organize-type)
                         (lambda () 'action)))
                (org-tasklet-triage-items))))
        (kill-buffer)))
    (should (= 0 (org-tasklet-inbox-count)))
    (let ((text (org-tasklet--read-file-string (org-tasklet-tasks-file))))
      (should (string-match-p "\\*\\* TODO First" text))
      (should (string-match-p "\\*\\* TODO Second" text))
      (should (string-match-p "\\*\\* TODO Third" text)))))

(ert-deftest org-tasklet-triage-items-quit-stops-after-current ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-current-buffer (find-file-noselect (org-tasklet-inbox-file))
      (unwind-protect
          (progn
            (erase-buffer)
            (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
                    "* TODO First\n"
                    "* TODO Second\n")
            (org-mode)
            (goto-char (point-min))
            (let ((org-tasklet-triage-ask-tags nil)
                  (calls 0))
              (cl-letf (((symbol-function 'org-tasklet--read-organize-type)
                         (lambda ()
                           (setq calls (1+ calls))
                           (if (> calls 1)
                               (signal 'quit nil)
                             'action))))
                (org-tasklet-triage-items))))
        (kill-buffer)))
    ;; 第一个 item 已处理，第二个 item 在 C-g 时保留在 inbox。
    (should (= 1 (org-tasklet-inbox-count)))
    (should (string-match-p "\\*\\* TODO First"
                            (org-tasklet--read-file-string
                             (org-tasklet-tasks-file))))
    (should (string-match-p "\\* TODO Second"
                            (org-tasklet--read-file-string
                             (org-tasklet-inbox-file))))))

(ert-deftest org-tasklet-triage-items-opens-inbox-from-other-buffer ()
  (org-tasklet-test--with-temp-dir
    (org-tasklet-ensure-files)
    (with-temp-file (org-tasklet-inbox-file)
      (insert "#+TODO: TODO NEXT | DONE CNCL\n\n"
              "* TODO Only item\n"))
    (unwind-protect
        (with-temp-buffer
          (let ((org-tasklet-triage-ask-tags nil))
            (cl-letf (((symbol-function 'org-tasklet--read-organize-type)
                       (lambda () 'action)))
              (org-tasklet-triage-items)))
          ;; 命令应已切换到 inbox buffer。
          (should (org-tasklet-inbox-buffer-p)))
      (when (get-file-buffer (org-tasklet-inbox-file))
        (kill-buffer (get-file-buffer (org-tasklet-inbox-file)))))
    (should (= 0 (org-tasklet-inbox-count)))
    (should (string-match-p "\\*\\* TODO Only item"
                            (org-tasklet--read-file-string
                             (org-tasklet-tasks-file))))))

(ert-deftest org-tasklet-registers-new-and-legacy-protocols ()
  (let ((org-protocol-protocol-alist nil)
        (org-tasklet-protocols '("tasklet-capture"))
        (org-tasklet-legacy-protocols '("gtd-capture")))
    (org-tasklet-register-org-protocol)
    (should (cl-find "tasklet-capture" org-protocol-protocol-alist
                     :key (lambda (entry)
                            (plist-get (cdr entry) :protocol))
                     :test #'string=))
    (should (cl-find "gtd-capture" org-protocol-protocol-alist
                     :key (lambda (entry)
                            (plist-get (cdr entry) :protocol))
                     :test #'string=))))

(provide 'org-tasklet-test)

;;; org-tasklet-test.el 到此结束
