;;; shallan-artwork.el --- Managing album artwork -*- lexical-binding: t -*-

;;; Commentary:

;; Utility functions for generating and displaying thumbnail and
;; full-resolution versions of album artwork.

;;; Code:

(require 'shallan-object)

(defun shallan--get-thumbnail-filename (hash width)
  "Given SHA256 HASH string and pixel WIDTH, return absolute filesystem path.
This path is where the thumbnail for the artwork with the given
HASH with the given WIDTH will be stored. The thumbnail may or
may not actually exist, but if it does, the returned path is
where it will be."
  (expand-file-name
   (number-to-string width)
   (expand-file-name
    hash
    (expand-file-name
     "thumbnails"
     shallan-library-dir))))

(defun shallan--thumbnail-sentinel (proc event)
  "Process sentinel for `shallan--generate-thumbnail'."
  (with-current-buffer (process-buffer proc)
    (goto-char (point-max))
    (let ((inhibit-read-only t))
      (insert event))
    (unless (process-live-p proc)
      (when-let ((callback (process-get proc 'callback)))
        (process-put proc 'callback nil)
        (if (zerop (process-exit-status proc))
            (funcall callback (process-get proc 'thumbnail))
          (pop-to-buffer (current-buffer))
          (error "Shallan failed to convert thumbnail"))))))

(defun shallan--get-thumbnail (hash width callback)
  "Get path to thumbnail, generating it if it doesn't exist.
HASH is the SHA256 string by which the image can be found in the
object store, and WIDTH is the number of pixels of the thumbnail.
CALLBACK is invoked with the path to the generated thumbnail
after it is written, assuming no error occurs."
  (let ((thumbnail (shallan--get-thumbnail-filename hash width)))
    (if (file-exists-p thumbnail)
        (funcall callback thumbnail)
      (make-directory (file-name-directory thumbnail) 'parents)
      (let ((buf (get-buffer-create
                  (shallan--get-unique-buffer-name
                   " *shallan thumbnail %d*"))))
        (with-current-buffer buf
          (special-mode))
        (let ((proc (make-process
                     :name "shallan-thumbnail"
                     :buffer buf
                     :command `("convert"
                                "-resize"
                                ,(number-to-string width)
                                ,(shallan--get-object-filename hash)
                                ,thumbnail)
                     :sentinel #'shallan--thumbnail-sentinel)))
          (process-put proc 'callback callback)
          (process-put proc 'thumbnail thumbnail))))))

(defun shallan--get-thumbnails (specs callback)
  "Get paths to multiple thumbnails.
SPECS is a list of cons cells (HASH . WIDTH) as in
`shallan--get-thumbnail'. Generate all thumbnails that don't
already exist, in parallel. Then invoke CALLBACK with a list of
paths to the thumbnails in the same order as in SPECS."
  (let* ((idx 0)
         (num-left (length specs))
         (results (make-vector num-left nil)))
    (dolist (spec specs)
      (let ((idx idx))  ; make copy
        (shallan--get-thumbnail
         (car spec) (cdr spec)
         (lambda (thumbnail)
           (aset results idx thumbnail)
           (cl-decf num-left)
           (when (<= num-left 0)
             (funcall callback (seq-into results 'list))))))
      (cl-incf idx))))

(provide 'shallan-artwork)

;;; shallan-artwork.el ends here
