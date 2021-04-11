;;; shallan-mode.el --- Major mode for UI -*- lexical-binding: t -*-

;;; Commentary:

;; UI primitives and the base major mode.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

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
  (if-let ((func (get-text-property (point) 'shallan-visit)))
      (funcall func)
    (user-error "Nothing to visit at point")))

(defun shallan-play ()
  "Play the thing at point in a new buffer."
  (interactive)
  (if-let ((func (get-text-property (point) 'shallan-play)))
      (funcall func)
    (user-error "Nothing to play at point")))

(defvar shallan-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'shallan-visit)
    (define-key map (kbd "SPC") #'shallan-play)
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

(provide 'shallan-mode)

;;; shallan-mode.el ends here
