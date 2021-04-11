;;; shallan-config.el --- User options -*- lexical-binding: t -*-

;;; Commentary:

;; User options for Shallan, and functions that read configuration.

;;; Code:

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
    (user-error "Program sqlite3 is not installed"))
  (unless (executable-find "mpg321")
    (user-error "Program mpg321 is not installed")))

(defcustom shallan-device-name (format "emacs-%s" (system-name))
  "Name of this device. Used for play queue syncing.
This should be unique across different devices."
  :type 'string)

(provide 'shallan-config)

;;; shallan-config.el ends here
