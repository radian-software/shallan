;;; shallan-query.el --- SQLite queries -*- lexical-binding: t -*-

;;; Commentary:

;; Low-level functions for performing SQLite queries.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(require 'shallan-config)

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
  (when (listp query)
    (setq query (format
                 "BEGIN TRANSACTION; %s; COMMIT TRANSACTION"
                 (string-join query "; "))))
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
      (insert query "\n\n")
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

(defun shallan-get-uuid ()
  "Generate UUID for use as database primary key."
  (format
   "%08x%08x%08x%08x"
   (random #x100000000)
   (random #x100000000)
   (random #x100000000)
   (random #x100000000)))

(provide 'shallan-query)

;;; shallan-query.el ends here
