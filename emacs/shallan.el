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
      (with-current-buffer (process-buffer proc)
        (funcall callback))
      (kill-buffer (process-buffer proc))
      (kill-buffer (process-get proc 'stderr-buffer)))))

(defun shallan--sqlite-query (query &optional callback)
  "Execute SQL QUERY string against database.
Invoke CALLBACK in a buffer with the raw query results from
stdout. The stderr is in the `stderr-buffer' property of the
process, which can be retrieved using `get-buffer-process' and
`process-get'. Once CALLBACK returns, delete the buffer, unless
there was an error."
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

(provide 'shallan)

;;; shallan.el ends here
