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

;; Main entry point for Shallan.

;;; Code:

(require 'shallan-config)
(require 'shallan-mode)
(require 'shallan-play)
(require 'shallan-query)
(require 'shallan-ui)

(provide 'shallan)

;;; shallan.el ends here
