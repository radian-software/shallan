;;; shallan-ui.el --- User-facing functions -*- lexical-binding: t -*-

;;; Commentary:

;; User-facing commands and high-level UI components.

;;; Code:

(require 'let-alist)

(require 'shallan-config)

;;;###autoload
(defun shallan-list-albums ()
  "Display list of albums."
  (interactive)
  (shallan-display
   :buffer "albums"
   :mode "Albums"
   :query "SELECT DISTINCT album FROM songs ORDER BY album_sort COLLATE NOCASE ASC"
   :render (lambda (albums)
             (insert albums)
             (put-text-property
              (point-min) (point-max)
              'shallan-visit
              (lambda ()
                (shallan-show-album
                 (buffer-substring-no-properties
                  (point-at-bol) (point-at-eol))))))))

;;;###autoload
(defun shallan-show-album (&optional album)
  "Display songs in album."
  (interactive)
  (if album
      (shallan-display
       :buffer (format "album: %s" album)
       :mode "Album"
       :query `((album-data
                 . ,(format
                     "SELECT DISTINCT album_artist, year_released FROM songs WHERE album = %s ORDER BY album_artist, year_released"
                     (shallan-sqlite-quote album)))
                (songs-data
                 . ,(format
                     "SELECT disc, track, name FROM songs WHERE album = %s ORDER BY disc, track NULLS LAST"
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
                         (insert (format "%4s  %s\n" .track .name))))))))
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
(defun shallan-play-album (album song &optional callback)
  "Clear the play queue and add all songs of an ALBUM.
Set the playback position to given SONG within the album.
CALLBACK, if provided, is invoked with no arguments after work is
completed."
  (message "Playing %s from %s..." song album)
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
        (message "Playing %s from %s...done" song album)
        (when callback
          (funcall callback)))))))

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
        (if (string-empty-p hash)
            (user-error "No song selected")
          (shallan--mpg-play (string-remove-suffix "\n" hash) #'shallan-play-next)))))))

(defun shallan-play-next ()
  "Select and play the next song, if any, from the beginning."
  (interactive)
  (shallan--ensure-play-queue
   (lambda (playlist-id)
     (shallan-sqlite-query
      (format
       "SELECT song_hash FROM songs WHERE id IN (SELECT song_id FROM playlist_songs WHERE playlist_id = %s AND song_index IN (SELECT song_index + 1 AS song_index FROM playlists WHERE id = %s)) LIMIT 1"
       (shallan-sqlite-quote playlist-id)
       (shallan-sqlite-quote playlist-id))
      (lambda (hash)
        (unless (string-empty-p hash)
          (shallan--mpg-play hash #'shallan-play-next)))))))

(defun shallan-toggle-playback ()
  "Pause or resume playback."
  (interactive)
  (if shallan--mpg-playing
      (shallan--mpg-pause)
    (shallan--mpg-unpause)))

(provide 'shallan-ui)

;;; shallan-ui.el ends here
