;;; shallan.el --- Music library frontend -*- lexical-binding: t -*-

;; Copyright (C) 2021 Radon Rosborough

;; Author: Radon Rosborough <radon.neon@gmail.com>
;; Created: 5 Apr 2021
;; Homepage: https://github.com/raxod502/shallan
;; Keywords: applications
;; Package-Requires: ((emacs "26"))
;; SPDX-License-Identifier: MIT
;; Version: 0

;;; Commentary:

;; Please see https://github.com/raxod502/shallan for more information.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup shallan nil
  "Music library frontend."
  :group 'applications
  :prefix "shallan-")

(defcustom shallan-library-dir nil
  "Path to directory containing Shallan music library.
This directory will contain a SQLite3 database named
\"library.sqlite3\", and a directory named \"objects\"."
  :type 'directory)

(defun shallan--validate-environment ()
  "Validate environment setup for Shallan to work properly.
Check:
* `shallan-library-dir' must be set
* sqlite3 must be installed
If anything is wrong, throw `user-error'."
  (unless shallan-library-dir
    (user-error "User option `shallan-library-dir' is not set"))
  (unless (executable-find "sqlite3")
    (user-error "Program sqlite3 is not installed")))

(defun shallan--get-unique-buffer-name (format)
  "Return a name that is not used by any buffer.
FORMAT is a string for `format' which should take one %d
parameter."
  (cl-block nil
    (let ((num 1))
      (while t
        (let ((name (format format num)))
          (unless (get-buffer name)
            (cl-return name)))
        (cl-incf num)))))

(defun shallan--sqlite-sentinel (proc event)
  "Process sentinel for `shallan--sqlite-query'.
PROC is the process object and EVENT is the event string, per
usual."
  (with-current-buffer (process-get proc 'stderr-buffer)
    (goto-char (point-max))
    (let ((inhibit-read-only t))
      (insert event)))
  (unless (process-live-p proc)
    (when-let ((callback (process-get proc 'callback)))
      (process-put proc 'callback nil)
      (unless (zerop (process-exit-status proc))
        (pop-to-buffer (process-get proc 'stderr-buffer))
        (display-buffer (process-buffer proc))
        (error "Shallan SQLite query failed"))
      (let ((text (with-current-buffer (process-buffer proc)
                    (buffer-string))))
        (kill-buffer (process-buffer proc))
        (kill-buffer (process-get proc 'stderr-buffer))
        (funcall callback text)))))

(defun shallan-sqlite-query (query &optional callback)
  "Execute SQL QUERY string against database.
Invoke CALLBACK with the query results as a string. Delete the
process buffer before invoking CALLBACK, unless there was an
error (in which case display the process buffer and do not invoke
CALLBACK)."
  (let ((stdout-buffer (get-buffer-create
                        (shallan--get-unique-buffer-name
                         " *shallan query %d*")))
        (stderr-buffer (get-buffer-create
                        (shallan--get-unique-buffer-name
                         " *shallan query stderr %d*")))
        (db-file (expand-file-name
                  "library.sqlite3"
                  shallan-library-dir)))
    (unless (file-exists-p db-file)
      (error "Shallan database does not exist"))
    (with-current-buffer stdout-buffer
      (special-mode))
    (with-current-buffer stderr-buffer
      (special-mode))
    (let ((proc (make-process
                 :name "shallan query"
                 :buffer stdout-buffer
                 :stderr stderr-buffer
                 :command `("sqlite3" ,db-file)
                 :sentinel #'shallan--sqlite-sentinel)))
      (process-put proc 'stderr-buffer stderr-buffer)
      (process-put proc 'callback (or callback #'identity))
      (process-send-string proc query)
      (process-send-eof proc))))

(defmacro shallan--save-destructive-excursion (&rest body)
  "Try to preserve position of point while executing BODY.
This works by saving the text immediately surrounding point in
the current buffer, then searching for it again after BODY is
done. That way, even if BODY deletes and re-inserts the text of
the buffer, point may still be preserved."
  (declare (indent 0))
  (let ((orig-line (gensym "orig-line-number"))
        (orig-line-text (gensym "orig-line"))
        (orig-column (gensym "orig-column"))
        (orig-window-starts (gensym "orig-window-starts")))
    `(let ((,orig-line (line-number-at-pos))
           (,orig-line-text (buffer-substring-no-properties
                             (point-at-bol) (point-at-eol)))
           (,orig-column (current-column))
           (,orig-window-starts (make-hash-table :test #'eq)))
       (dolist (win (get-buffer-window-list nil nil t))
         (puthash win (window-start win) ,orig-window-starts))
       ,@body
       (goto-char (point-min))
       (forward-line (1- ,orig-line))
       (let* ((before-line (save-excursion
                             (search-backward ,orig-line-text nil 'noerror)
                             (line-number-at-pos)))
              (after-line (save-excursion
                            (search-forward ,orig-line-text nil 'noerror)
                            (line-number-at-pos)))
              (before-dist (when before-line
                             (- ,orig-line before-line)))
              (after-dist (when after-line
                            (- after-line ,orig-line)))
              (new-line (cond
                         ((null after-dist) before-line)
                         ((null before-dist) after-line)
                         ((< before-dist after-dist) before-line)
                         (t after-line))))
         (when new-line
           (goto-char (point-min))
           (forward-line (1- new-line)))
         (move-to-column ,orig-column)
         (maphash
          (lambda (win start)
            (set-window-start win start))
          ,orig-window-starts)))))

(defvar-local shallan--query-function nil
  "Function that will fetch data for `shallan--render-function'.
It gets a single CALLBACK argument which should be invoked with
the data to pass to `shallan--render-function'.")

(defvar-local shallan--render-function nil
  "Function that will populate the current buffer with text.
This gets a single argument, the value `shallan--query-function'
passed to its CALLBACK argument. It must execute synchronously.")

(defun shallan-refresh (&optional callback)
  "Refresh the contents of the current Shallan buffer.
If CALLBACK is provided then invoke it with no arguments in the
same buffer when the refresh is complete."
  (unless (derived-mode-p #'shallan-mode)
    (error "Cannot invoke `shallan-refresh' outside of `shallan-mode'"))
  (let ((buf (current-buffer)))
    (message "Refreshing...")
    (funcall shallan--query-function
             (lambda (data)
               (with-current-buffer buf
                 (shallan--save-destructive-excursion
                   (let ((inhibit-read-only t))
                     (erase-buffer)
                     (funcall shallan--render-function data)
                     (message "Refreshing...done")
                     (when callback
                       (funcall callback)))))))))

(defun shallan-visit ()
  "Visit the thing at point in a new buffer."
  (interactive)
  (message "TODO"))

(defvar shallan-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'shallan-visit)
    map)
  "Keymap for `shallan-list-albums-mode'.")

(defun shallan--revert-buffer-function (&rest _)
  "Wrapper of `shallan-refresh' for `revert-buffer-function'."
  (shallan-refresh))

(define-derived-mode shallan-mode special-mode "Shallan"
  "Major mode that lists the albums in your library."
  (setq-local revert-buffer-function #'shallan--revert-buffer-function))

(cl-defun shallan-display (&key buffer-name mode-name query render)
  "Create and display an interactive Shallan buffer.
BUFFER-NAME is the name of the buffer. If one exists already then
it will be refreshed and displayed. MODE-NAME is the major mode
name for display in the mode line. RENDER is the rendering
function, which inserts text into the current buffer. RENDER
should take one CALLBACK argument which it invokes with no
arguments when the rendering is complete."
  (unless buffer-name
    (error "Argument BUFFER-NAME not passed to `shallan-display'"))
  (unless mode-name
    (error "Argument MODE-NAME not passed to `shallan-display'"))
  (unless query
    (error "Argument QUERY not passed to `shallan-display'"))
  (shallan--validate-environment)
  (with-current-buffer (get-buffer-create buffer-name)
    (shallan-mode)
    (setq-local shallan--query-function
                (if (functionp query)
                    query
                  (lambda (callback)
                    (shallan-sqlite-query query callback))))
    (setq-local shallan--render-function (or render #'insert))
    (shallan-refresh
     (lambda ()
       (pop-to-buffer (current-buffer))))))

(defun shallan-list-albums ()
  "Display list of albums."
  (interactive)
  (shallan-display
   :buffer-name "*shallan albums*"
   :mode-name "Shallan/Albums"
   :query "SELECT DISTINCT album FROM songs ORDER BY album_sort COLLATE NOCASE ASC"))

(provide 'shallan)

;;; shallan.el ends here
