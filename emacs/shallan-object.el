;;; shallan-object.el --- Retrieve from object store -*- lexical-binding: t -*-

;;; Commentary:

;; Utility functions for manipulating the Shallan content-addressable
;; object store.

;;; Code:

(require 'shallan-config)

(defun shallan--get-object-filename (hash)
  "Given SHA256 HASH string, return absolute filesystem path.
An object with that hash may or may not exist in the object
store, but if it does, the returned path is where it will be."
  (expand-file-name
   (substring hash 2)
   (expand-file-name
    (substring hash 0 2)
    (expand-file-name
     "objects"
     shallan-library-dir))))

(provide 'shallan-object)

;;; shallan-object.el ends here
