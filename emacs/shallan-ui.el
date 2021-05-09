;;; shallan-ui.el --- User-facing functions -*- lexical-binding: t -*-

;;; Commentary:

;; User-facing commands and high-level UI components.

;;; Code:

(require 'cl-lib)
(require 'let-alist)
(require 'subr-x)

(require 'shallan-artwork)
(require 'shallan-config)
(require 'shallan-mode)
(require 'shallan-object)
(require 'shallan-play)
(require 'shallan-query)

;;;###autoload
(defun shallan-list-albums ()
  "Display list of albums."
  (interactive)
  (shallan-display
   :buffer "albums"
   :mode "Albums"
   :query "SELECT DISTINCT album FROM songs ORDER BY album_sort COLLATE NOCASE"
   :render (lambda (albums)
             (insert albums)
             (put-text-property
              (point-min) (point-max)
              'shallan-visit
              (lambda ()
                (shallan-show-album
                 (buffer-substring-no-properties
                  (point-at-bol) (point-at-eol)))))
             (put-text-property
              (point-min) (point-max)
              'shallan-play
              (lambda ()
                (shallan-play-album
                 (buffer-substring-no-properties
                  (point-at-bol) (point-at-eol))))))))

(defun shallan-browse-album-move-left ()
  "Move left in the album browsing view."
  (interactive)
  (backward-char))

(defun shallan-browse-album-move-right ()
  "Move right in the album browsing view."
  (interactive)
  (save-restriction
    (narrow-to-region 1 (buffer-size))
    (forward-char)))

(defun shallan-browse-album-move-up ()
  "Move up in the album browsing view."
  (interactive)
  (line-move-visual -1))

(defun shallan-browse-album-move-down ()
  "Move down in the album browsing view."
  (interactive)
  ;; Just calling `next-line' should work, but doesn't; see
  ;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=48170.
  (line-move-visual 1))

(defcustom shallan-browse-album-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<left>") #'shallan-browse-album-move-left)
    (define-key map (kbd "<right>") #'shallan-browse-album-move-right)
    (define-key map (kbd "<up>") #'shallan-browse-album-move-up)
    (define-key map (kbd "<down>") #'shallan-browse-album-move-down)
    map)
  "Keymap for `shallan-browse-albums' buffer extra bindings."
  :type 'lisp)

;;;###autoload
(defun shallan-browse-albums ()
  "Display grid view of albums."
  (interactive)
  (shallan-display
   :buffer "albums grid"
   :mode "Albums/Grid"
   :query (lambda (callback)
            (shallan-sqlite-query
             "SELECT DISTINCT album, artwork_hash FROM songs ORDER BY album_sort COLLATE NOCASE"
             (lambda (data)
               (let ((rows (shallan-parse-table data '(album artwork-hash))))
                 (shallan--get-thumbnails
                  (mapcar
                   (lambda (row)
                     (cons (alist-get 'artwork-hash row)
                           shallan-grid-thumbnail-resolution))
                   rows)
                  (lambda (thumbnails)
                    (funcall
                     callback
                     (cl-mapcar
                      (lambda (row thumbnail)
                        `((album . ,(alist-get 'album row))
                          (thumbnail . ,thumbnail)))
                      rows
                      thumbnails))))))))
   :render (lambda (data)
             (dolist (datum data)
               (let-alist datum
                 (insert
                  (propertize
                   " "
                   'display
                   (create-image
                    .thumbnail
                    nil nil
                    :width shallan-grid-thumbnail-width
                    :margin shallan-grid-thumbnail-margin)
                   'shallan-visit
                   (lambda ()
                     (shallan-show-album .album))
                   'shallan-play
                   (lambda ()
                     (shallan-play-album .album)))))))
   :keymap shallan-browse-album-keymap
   :post-command (lambda ()
                   (save-restriction
                     (widen)
                     (goto-char
                      (min (point) (1- (point-max))))))))

;;;###autoload
(defun shallan-show-album (&optional album)
  "Display songs in given ALBUM.
Nil ALBUM means select one using `completing-read'."
  (interactive)
  (if album
      (shallan-display
       :buffer (format "album: %s" album)
       :mode "Album"
       :query (lambda (callback)
                (shallan-sqlite-query-parallel
                 `((album-data
                    . ,(format
                        "SELECT DISTINCT album_artist, year_released, artwork_hash FROM songs WHERE album = %s ORDER BY album_artist, year_released"
                        (shallan-sqlite-quote album)))
                   (songs-data
                    . ,(format
                        "SELECT disc, track, name FROM songs WHERE album = %s ORDER BY disc, track NULLS LAST"
                        (shallan-sqlite-quote album))))
                 (lambda (data)
                   (let-alist data
                     (shallan--get-thumbnails
                      (let ((hashes (seq-uniq
                                     (mapcar
                                      (lambda (row)
                                        (alist-get 'artwork-hash row))
                                      (shallan-parse-table
                                       .album-data
                                       '(album-artist year-released artwork-hash))))))
                        (mapcar
                         (lambda (hash)
                           (cons hash shallan-album-thumbnail-resolution))
                         hashes))
                      (lambda (thumbnails)
                        (funcall
                         callback
                         `((thumbnails . ,thumbnails) ,@data))))))))
       :render (lambda (data)
                 (let-alist data
                   (let ((rows
                          (shallan-parse-table
                           .album-data
                           '(album-artist year-released artwork-hash))))
                     (unless rows
                       (error "No such album: %s" album))
                     (dolist (thumbnail .thumbnails)
                       (insert
                        (propertize
                         " "
                         'display
                         (create-image
                          thumbnail
                          nil nil
                          :width shallan-album-thumbnail-width
                          :margin shallan-album-thumbnail-margin)
                         'shallan-play
                         (lambda ()
                           (shallan-play-album album)))))
                     (insert "\n\n")
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
                         (insert (propertize
                                  (format "%4s  %s\n" .track .name)
                                  'shallan-play
                                  (lambda ()
                                    (shallan-play-album album .name))))))))))
    (message "Listing albums...")
    (shallan-sqlite-query
     "SELECT DISTINCT album FROM songs ORDER BY album_sort COLLATE NOCASE ASC"
     (lambda (albums)
       (message "Listing albums...done")
       (shallan-show-album
        (completing-read
         "Album: "
         (split-string albums "\n" 'omit-nulls)))))))

(defun shallan--ensure-play-queue (callback)
  "Ensure play queue for this device is set up.
Then invoke CALLBACK with the relevant playlist ID."
  (shallan-sqlite-query
   (format
    "SELECT playlist_id FROM play_queues WHERE device = %s LIMIT 1"
    (shallan-sqlite-quote shallan-device-name))
   (lambda (playlist-id)
     (if (string-empty-p playlist-id)
         (let ((insert-queue
                (lambda (playlist-id)
                  (shallan-sqlite-query
                   (format
                    "INSERT INTO play_queues (id, device, playlist_id) VALUES (%s, %s, %s)"
                    (shallan-sqlite-quote (shallan-get-uuid))
                    (shallan-sqlite-quote shallan-device-name)
                    (shallan-sqlite-quote playlist-id))
                   (lambda (_)
                     (funcall callback playlist-id))))))
           (shallan-sqlite-query
            "SELECT id FROM playlists WHERE name = 'Up Next' LIMIT 1"
            (lambda (playlist-id)
              (if (string-empty-p playlist-id)
                  (let ((playlist-id (shallan-get-uuid)))
                    (shallan-sqlite-query
                     (format
                      "INSERT INTO playlists (id, name) VALUES (%s, 'Up Next')"
                      (shallan-sqlite-quote playlist-id))
                     (lambda (_)
                       (funcall insert-queue playlist-id))))
                (funcall insert-queue (string-remove-suffix "\n" playlist-id))))))
       (funcall callback (string-remove-suffix "\n" playlist-id))))))

;;;###autoload
(defun shallan-play-album (album &optional song callback)
  "Clear the play queue and add all songs of an ALBUM.
Set the playback position to given SONG (defaults to the first)
within the album. CALLBACK, if provided, is invoked with no
arguments after work is completed."
  (message
   "Playing album %s%s..."
   album
   (if song
       (format " starting at song %s" song)
     ""))
  (let* ((orig-song song)
         (play
          (lambda (song)
            (shallan--ensure-play-queue
             (lambda (playlist-id)
               (shallan-sqlite-query
                (list
                 (format
                  "DELETE FROM playlist_songs WHERE playlist_id = %s"
                  (shallan-sqlite-quote playlist-id))
                 (format
                  "INSERT INTO playlist_songs (song_id, playlist_id, song_index) SELECT id AS song_id, %s AS playlist_id, row_number() OVER (ORDER BY disc, track NULLS LAST) AS song_index FROM songs WHERE album = %s ORDER BY disc, track NULLS LAST"
                  (shallan-sqlite-quote playlist-id)
                  (shallan-sqlite-quote album))
                 (format
                  "UPDATE playlists SET song_index = (SELECT song_index FROM (SELECT name, row_number() OVER (ORDER BY disc, track NULLS LAST) AS song_index FROM songs WHERE album = %s) WHERE name = %s) WHERE id = %s"
                  (shallan-sqlite-quote album)
                  (shallan-sqlite-quote song)
                  (shallan-sqlite-quote playlist-id)))
                (lambda (_)
                  (shallan-play-current)
                  (message
                   "Playing album %s%s...done"
                   album
                   (if orig-song
                       (format " starting at song %s" orig-song)
                     ""))
                  (when callback
                    (funcall callback)))))))))
    (if song
        (funcall play song)
      (shallan-sqlite-query
       (format
        "SELECT name FROM songs WHERE album = %s ORDER BY disc, track NULLS LAST LIMIT 1"
        (shallan-sqlite-quote album))
       (lambda (song)
         (funcall play (string-remove-suffix "\n" song)))))))

(defun shallan-play-current ()
  "Play the currently selected song from the beginning."
  (interactive)
  (shallan--ensure-play-queue
   (lambda (playlist-id)
     (shallan-sqlite-query
      (format
       "SELECT song_hash FROM songs WHERE id IN (SELECT song_id FROM playlist_songs WHERE playlist_id = %s AND song_index IN (SELECT song_index FROM playlists WHERE id = %s)) LIMIT 1"
       (shallan-sqlite-quote playlist-id)
       (shallan-sqlite-quote playlist-id))
      (lambda (hash)
        (unless (string-empty-p hash)
          (shallan--mpg-play (string-remove-suffix "\n" hash) #'shallan-play-next)))))))

(defun shallan-play-next ()
  "Select and play the next song, if any, from the beginning."
  (interactive)
  (shallan--ensure-play-queue
   (lambda (playlist-id)
     (shallan-sqlite-query
      (format
       "UPDATE playlists SET song_index = song_index + 1 WHERE id = %s"
       (shallan-sqlite-quote playlist-id))
      (lambda (_)
        (shallan-play-current))))))

(defun shallan-play-prev ()
  "Select and play the previous song, if any, from the beginning."
  (interactive)
  (shallan--ensure-play-queue
   (lambda (playlist-id)
     (shallan-sqlite-query
      (format
       "UPDATE playlists SET song_index = song_index - 1 WHERE id = %s"
       (shallan-sqlite-quote playlist-id))
      (lambda (_)
        (shallan-play-current))))))

(defun shallan-unpause ()
  "Resume playback."
  (interactive)
  (shallan--mpg-unpause))

(defalias 'shallan-play #'shallan-unpause
  "Resume playback.")

(defun shallan-pause ()
  "Pause playback."
  (interactive)
  (shallan--mpg-pause))

(defun shallan-toggle-playback ()
  "Pause or resume playback."
  (interactive)
  (if shallan--mpg-playing
      (shallan--mpg-pause)
    (shallan--mpg-unpause)))

(provide 'shallan-ui)

;;; shallan-ui.el ends here
