;;; shallan-util.el --- Misc utility functions -*- lexical-binding: t -*-

;;; Commentary:

;; Miscellaneous shared utility functions.

;;; Code:

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

(provide 'shallan-util)

;;; shallan-util.el ends here
