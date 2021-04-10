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
(require 'let-alist)
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

(defcustom shallan-sqlite-separator ?|
  "Separator character used for SQLite queries.
This character may not appear in any field stored in the database."
  :type 'character)

(defun shallan-sqlite-quote (string)
  "Quote STRING for use in a SQLite query.
This means wrapping it in single quotes and doubling any existing
single quotes."
  (format "'%s'" (replace-regexp-in-string
                  "'" "''" string
                  'fixedcase 'literal)))

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
                 :command `("sqlite3"
                            "-separator"
                            ,(char-to-string shallan-sqlite-separator)
                            ,db-file)
                 :sentinel #'shallan--sqlite-sentinel)))
      (process-put proc 'stderr-buffer stderr-buffer)
      (process-put proc 'callback (or callback #'identity))
      (process-send-string proc query)
      (process-send-eof proc))))

(defun shallan--map-async (func list callback)
  "Map FUNC over LIST asynchronously, invoking CALLBACK with results.
FUNC takes two arguments, a list item and a callback of one
argument. CALLBACK gets a list of the items FUNC passed to each
callback individually. FUNC is invoked in parallel."
  (let ((num-completed 0)
        (vec (make-vector (length list) nil))
        (idx 0))
    (dolist (item list)
      (let ((idx idx))  ; make copy
        (funcall
         func
         item
         (lambda (result)
           (aset vec idx result)
           (cl-incf num-completed)
           (when (>= num-completed (length vec))
             (funcall callback (mapcar #'identity vec))))))
      (cl-incf idx))))

(defun shallan-sqlite-query-parallel (queries &optional callback)
  "Execute multiple SQL QUERIES against database, in parallel.
QUERIES is an alist whose keys are symbols and whose values are
SQL query strings. CALLBACK is passed a corresponding alist where
the values have been replaced with the query results."
  (shallan--map-async
   (lambda (link callback)
     (shallan-sqlite-query
      (cdr link)
      (lambda (result)
        (funcall
         callback
         (cons (car link) result)))))
   queries
   callback))

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
  (setq-local revert-buffer-function #'shallan--revert-buffer-function)
  (hl-line-mode +1))

(cl-defun shallan-display (&key buffer mode query render)
  "Create and display an interactive Shallan buffer.
BUFFER-NAME is the name of the buffer. If one exists already then
it will be refreshed and displayed. MODE-NAME is the major mode
name for display in the mode line. RENDER is the rendering
function, which inserts text into the current buffer. RENDER
should take one CALLBACK argument which it invokes with no
arguments when the rendering is complete."
  (shallan--validate-environment)
  (with-current-buffer (get-buffer-create (format "*shallan %s*" buffer))
    (shallan-mode)
    (setq-local mode-name (format "Shallan/%s" mode))
    (setq-local shallan--query-function
                (cond
                 ((functionp query)
                  query)
                 ((listp query)
                  (lambda (callback)
                    (shallan-sqlite-query-parallel query callback)))
                 (t
                  (lambda (callback)
                    (shallan-sqlite-query query callback)))))
    (setq-local shallan--render-function (or render #'insert))
    (shallan-refresh
     (lambda ()
       (pop-to-buffer (current-buffer))))))

(defun shallan-parse-table (table fields)
  "Parse TABLE of SQL query results.
FIELDS is a list of symbols for the columns in the table. Return
a list of alists mapping FIELDS to their respective values in
each row of the table."
  (let ((rows nil))
    (replace-regexp-in-string
     (format
      "\\(?:^%s$\\)\n\\|\\(\\)"
      (string-join
       (make-list
        (length fields)
        (format "\\([^%c]*\\)" shallan-sqlite-separator))
       (regexp-quote (char-to-string shallan-sqlite-separator))))
     (lambda (match)
       (prog1 ""
         (when (match-string (1+ (length fields)) table)
           (with-current-buffer (get-buffer-create " *shallan query parse*")
             (special-mode)
             (let ((inhibit-read-only t))
               (erase-buffer)
               (insert table))
             (goto-char (match-beginning 0))
             (pop-to-buffer (current-buffer)))
           (error "Failed to parse %d fields from query row" (length fields)))
         (push
          (cl-mapcar
           (lambda (field num)
             (cons
              field
              (match-string num match)))
           fields
           (number-sequence 1 (length fields)))
          rows)))
     table
     'fixedcase)
    (nreverse rows)))

(defun shallan-list-albums ()
  "Display list of albums."
  (interactive)
  (shallan-display
   :buffer "albums"
   :mode "Albums"
   :query "SELECT DISTINCT album FROM songs ORDER BY album_sort COLLATE NOCASE ASC"))

(defun shallan-show-album (album)
  "Display songs in album."
  (shallan-display
   :buffer (format "album: %s" album)
   :mode "Album"
   :query `((album-data
             . ,(format
                 "SELECT DISTINCT album_artist, year_released FROM songs WHERE album = %s ORDER BY album_artist, year_released"
                 (shallan-sqlite-quote album)))
            (songs-data
             . ,(format
                 "SELECT disc, track, name FROM songs WHERE album = %s ORDER BY disc, track"
                 (shallan-sqlite-quote album))))
   :render (lambda (data)
             (let-alist data
               (let ((rows
                      (shallan-parse-table
                       .album-data
                       '(album-artist year-released))))
                 (unless rows
                   (error "No such album: %s" album))
                 (let* ((album-artists (seq-uniq
                                        (mapcar
                                         (lambda (row)
                                           (alist-get 'album-artist row))
                                         rows)))
                        (years-released (seq-uniq
                                         (mapcar
                                          (lambda (row)
                                            (alist-get 'year-released row))
                                          rows)))
                        (min-year (car years-released))
                        (max-year (car (last years-released)))
                        (years (if (string= min-year max-year)
                                   min-year
                                 (format "%s-%s" min-year max-year))))
                   (insert (format "%s - %s (%s)\n\n"
                                   album
                                   (string-join album-artists ", ")
                                   years))))
               (let ((cur-disc ""))
                 (dolist (row (shallan-parse-table .songs-data '(disc track name)))
                   (let-alist row
                     (unless (string= .disc cur-disc)
                       (if (string-empty-p .disc)
                           (insert "[No disc]\n")
                         (insert (format "[Disc %s]\n" .disc)))
                       (setq cur-disc .disc))
                     (insert (format "%4s  %s\n" .track .name)))))))))

(provide 'shallan)

;;; shallan.el ends here
