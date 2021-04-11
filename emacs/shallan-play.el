;;; shallan-play.el --- Actually play music -*- lexical-binding: t -*-

;;; Commentary:

;; Control a media server.

;;; Code:

(require 'subr-x)

(require 'shallan-object)

(defvar shallan--mpg-proc nil
  "Shared MPG321 process for media playback.")

(defvar shallan--mpg-hash nil
  "SHA256 hash of media object currently being played.
This may also be nil.")

(defvar shallan--mpg-playing nil
  "Non-nil means playback is currently active.")

(defvar shallan--mpg-bitrate nil
  "Bitrate of currently playing media.")

(defvar shallan--mpg-cur-seek nil
  "Current seek position in seconds from beginning.")

(defvar shallan--mpg-max-seek nil
  "Length of current media in seconds.")

(defvar shallan--mpg-s-regexp
  (format "@S %s" (string-join (make-list 12 "\\([^ ]+\\)") " "))
  "Regexp matching @S lines in mpg321 stdout.")

(defvar shallan--mpg-f-regexp
  (format "@F %s" (string-join (make-list 4 "\\([^ ]+\\)") " "))
  "Regexp matching @F lines in mpg321 stdout.")

(defvar shallan--mpg-callback nil
  "Function to invoke with no arguments after media finished playing.")

(defun shallan--mpg-filter (proc string)
  "Process filter for `shallan--mpg-proc'."
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert string)
        (goto-char (point-min))
        (while (looking-at "^\\(.*\\)\n")
          (let ((cmd (match-string 1)))
            ;; See /usr/share/doc/mpg321/README.remote for documentation on
            ;; the stdout format we are parsing here.
            (cond
             ((string-match shallan--mpg-f-regexp cmd)
              (let ((cur-frame (string-to-number (match-string 1 cmd)))
                    (frames-left (string-to-number (match-string 2 cmd))))
                (setq shallan--mpg-cur-seek
                      (/ (1- cur-frame) (float shallan--mpg-bitrate)))
                (setq shallan--mpg-max-seek
                      (/ (+ (1- cur-frame) frames-left)
                         (float shallan--mpg-bitrate)))))
             ((string-match shallan--mpg-s-regexp cmd)
              (setq shallan--mpg-playing t)
              (setq shallan--mpg-bitrate (string-to-number (match-string 3 cmd))))
             ((string-match "@P \\([0-3]\\)" cmd)
              (pcase (match-string 1 cmd)
                ((or "0" "3")
                 (setq shallan--mpg-playing nil)
                 (setq shallan--mpg-hash nil)
                 (setq shallan--mpg-bitrate nil)
                 (setq shallan--mpg-cur-seek nil)
                 (setq shallan--mpg-max-seek nil)
                 (when (equal "3" (match-string 1 cmd))
                   (when-let ((callback shallan--mpg-callback))
                     (setq shallan--mpg-callback nil)
                     (funcall callback))))
                ("1"
                 (setq shallan--mpg-playing nil))
                ("2"
                 (setq shallan--mpg-playing t))))))
          (delete-region (point) (1+ (point-at-eol))))))))

(defun shallan--mpg-play (hash &optional callback)
  "Play media object with given SHA256 HASH from beginning.
Invoke CALLBACK, if provided, with no arguments when media has
finished playing."
  (unless (process-live-p shallan--mpg-proc)
    (let ((buf (get-buffer-create " *shallan mpg*")))
      (with-current-buffer buf
        (special-mode))
      (setq shallan--mpg-proc
            (make-process
             :name "shallan-mpg"
             :buffer buf
             :command '("mpg321" "-R" "abc")
             :filter #'shallan--mpg-filter
             :noquery t))))
  (setq shallan--mpg-hash hash)
  (setq shallan--mpg-callback callback)
  (process-send-string
   shallan--mpg-proc
   (format "LOAD %s\n" (shallan--get-object-filename hash))))

(defun shallan--mpg-pause ()
  "Pause playback if possible."
  (when (and (process-live-p shallan--mpg-proc)
             shallan--mpg-playing)
    (process-send-string shallan--mpg-proc "PAUSE\n")))

(defun shallan--mpg-unpause ()
  "Resume playback if possible."
  (when (and (process-live-p shallan--mpg-proc)
             (not shallan--mpg-playing))
    (process-send-string shallan--mpg-proc "PAUSE\n")))

(provide 'shallan-play)

;;; shallan-play.el ends here
