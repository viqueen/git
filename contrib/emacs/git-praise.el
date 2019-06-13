;;; git-praise.el --- Minor mode for incremental praise for Git  -*- coding: utf-8 -*-
;;
;; Copyright (C) 2007  David Kågedal
;;
;; Authors:    David Kågedal <davidk@lysator.liu.se>
;; Created:    31 Jan 2007
;; Message-ID: <87iren2vqx.fsf@morpheus.local>
;; License:    GPL
;; Keywords:   git, version control, release management
;;
;; Compatibility: Emacs21, Emacs22 and EmacsCVS
;;                Git 1.5 and up

;; This file is *NOT* part of GNU Emacs.
;; This file is distributed under the same terms as GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.

;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
;; MA 02111-1307 USA

;; http://www.fsf.org/copyleft/gpl.html


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; Here is an Emacs implementation of incremental git-praise.  When you
;; turn it on while viewing a file, the editor buffer will be updated by
;; setting the background of individual lines to a color that reflects
;; which commit it comes from.  And when you move around the buffer, a
;; one-line summary will be shown in the echo area.

;;; Installation:
;;
;; To use this package, put it somewhere in `load-path' (or add
;; directory with git-praise.el to `load-path'), and add the following
;; line to your .emacs:
;;
;;    (require 'git-praise)
;;
;; If you do not want to load this package before it is necessary, you
;; can make use of the `autoload' feature, e.g. by adding to your .emacs
;; the following lines
;;
;;    (autoload 'git-praise-mode "git-praise"
;;              "Minor mode for incremental praise for Git." t)
;;
;; Then first use of `M-x git-praise-mode' would load the package.

;;; Compatibility:
;;
;; It requires GNU Emacs 21 or later and Git 1.5.0 and up
;;
;; If you'are using Emacs 20, try changing this:
;;
;;            (overlay-put ovl 'face (list :background
;;                                         (cdr (assq 'color (cddddr info)))))
;;
;; to
;;
;;            (overlay-put ovl 'face (cons 'background-color
;;                                         (cdr (assq 'color (cddddr info)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Code:

(eval-when-compile (require 'cl))			      ; to use `push', `pop'
(require 'format-spec)

(defface git-praise-prefix-face
  '((((background dark)) (:foreground "gray"
                          :background "black"))
    (((background light)) (:foreground "gray"
                           :background "white"))
    (t (:weight bold)))
  "The face used for the hash prefix."
  :group 'git-praise)

(defgroup git-praise nil
  "A minor mode showing Git praise information."
  :group 'git
  :link '(function-link git-praise-mode))


(defcustom git-praise-use-colors t
  "Use colors to indicate commits in `git-praise-mode'."
  :type 'boolean
  :group 'git-praise)

(defcustom git-praise-prefix-format
  "%h %20A:"
  "The format of the prefix added to each line in `git-praise'
mode. The format is passed to `format-spec' with the following format keys:

  %h - the abbreviated hash
  %H - the full hash
  %a - the author name
  %A - the author email
  %c - the committer name
  %C - the committer email
  %s - the commit summary
"
  :group 'git-praise)

(defcustom git-praise-mouseover-format
  "%h %a %A: %s"
  "The format of the description shown when pointing at a line in
`git-praise' mode. The format string is passed to `format-spec'
with the following format keys:

  %h - the abbreviated hash
  %H - the full hash
  %a - the author name
  %A - the author email
  %c - the committer name
  %C - the committer email
  %s - the commit summary
"
  :group 'git-praise)


(defun git-praise-color-scale (&rest elements)
  "Given a list, returns a list of triples formed with each
elements of the list.

a b => bbb bba bab baa abb aba aaa aab"
  (let (result)
    (dolist (a elements)
      (dolist (b elements)
        (dolist (c elements)
          (setq result (cons (format "#%s%s%s" a b c) result)))))
    result))

;; (git-praise-color-scale "0c" "04" "24" "1c" "2c" "34" "14" "3c") =>
;; ("#3c3c3c" "#3c3c14" "#3c3c34" "#3c3c2c" "#3c3c1c" "#3c3c24"
;; "#3c3c04" "#3c3c0c" "#3c143c" "#3c1414" "#3c1434" "#3c142c" ...)

(defmacro git-praise-random-pop (l)
  "Select a random element from L and returns it. Also remove
selected element from l."
  ;; only works on lists with unique elements
  `(let ((e (elt ,l (random (length ,l)))))
     (setq ,l (remove e ,l))
     e))

(defvar git-praise-log-oneline-format
  "format:[%cr] %cn: %s"
  "*Formatting option used for describing current line in the minibuffer.

This option is used to pass to git log --pretty= command-line option,
and describe which commit the current line was made.")

(defvar git-praise-dark-colors
  (git-praise-color-scale "0c" "04" "24" "1c" "2c" "34" "14" "3c")
  "*List of colors (format #RGB) to use in a dark environment.

To check out the list, evaluate (list-colors-display git-praise-dark-colors).")

(defvar git-praise-light-colors
  (git-praise-color-scale "c4" "d4" "cc" "dc" "f4" "e4" "fc" "ec")
  "*List of colors (format #RGB) to use in a light environment.

To check out the list, evaluate (list-colors-display git-praise-light-colors).")

(defvar git-praise-colors '()
  "Colors used by git-praise. The list is built once when activating git-praise
minor mode.")

(defvar git-praise-ancient-color "dark green"
  "*Color to be used for ancient commit.")

(defvar git-praise-autoupdate t
  "*Automatically update the praise display while editing")

(defvar git-praise-proc nil
  "The running git-praise process")
(make-variable-buffer-local 'git-praise-proc)

(defvar git-praise-overlays nil
  "The git-praise overlays used in the current buffer.")
(make-variable-buffer-local 'git-praise-overlays)

(defvar git-praise-cache nil
  "A cache of git-praise information for the current buffer")
(make-variable-buffer-local 'git-praise-cache)

(defvar git-praise-idle-timer nil
  "An idle timer that updates the praise")
(make-variable-buffer-local 'git-praise-cache)

(defvar git-praise-update-queue nil
  "A queue of update requests")
(make-variable-buffer-local 'git-praise-update-queue)

;; FIXME: docstrings
(defvar git-praise-file nil)
(defvar git-praise-current nil)

(defvar git-praise-mode nil)
(make-variable-buffer-local 'git-praise-mode)

(defvar git-praise-mode-line-string " praise"
  "String to display on the mode line when git-praise is active.")

(or (assq 'git-praise-mode minor-mode-alist)
    (setq minor-mode-alist
	  (cons '(git-praise-mode git-praise-mode-line-string) minor-mode-alist)))

;;;###autoload
(defun git-praise-mode (&optional arg)
  "Toggle minor mode for displaying Git praise

With prefix ARG, turn the mode on if ARG is positive."
  (interactive "P")
  (cond
   ((null arg)
    (if git-praise-mode (git-praise-mode-off) (git-praise-mode-on)))
   ((> (prefix-numeric-value arg) 0) (git-praise-mode-on))
   (t (git-praise-mode-off))))

(defun git-praise-mode-on ()
  "Turn on git-praise mode.

See also function `git-praise-mode'."
  (make-local-variable 'git-praise-colors)
  (if git-praise-autoupdate
      (add-hook 'after-change-functions 'git-praise-after-change nil t)
    (remove-hook 'after-change-functions 'git-praise-after-change t))
  (git-praise-cleanup)
  (let ((bgmode (cdr (assoc 'background-mode (frame-parameters)))))
    (if (eq bgmode 'dark)
	(setq git-praise-colors git-praise-dark-colors)
      (setq git-praise-colors git-praise-light-colors)))
  (setq git-praise-cache (make-hash-table :test 'equal))
  (setq git-praise-mode t)
  (git-praise-run))

(defun git-praise-mode-off ()
  "Turn off git-praise mode.

See also function `git-praise-mode'."
  (git-praise-cleanup)
  (if git-praise-idle-timer (cancel-timer git-praise-idle-timer))
  (setq git-praise-mode nil))

;;;###autoload
(defun git-repraise ()
  "Recalculate all praise information in the current buffer"
  (interactive)
  (unless git-praise-mode
    (error "Git-praise is not active"))

  (git-praise-cleanup)
  (git-praise-run))

(defun git-praise-run (&optional startline endline)
  (if git-praise-proc
      ;; Should maybe queue up a new run here
      (message "Already running git praise")
    (let ((display-buf (current-buffer))
          (praise-buf (get-buffer-create
                      (concat " git praise for " (buffer-name))))
          (args '("--incremental" "--contents" "-")))
      (if startline
          (setq args (append args
                             (list "-L" (format "%d,%d" startline endline)))))
      (setq args (append args
                         (list (file-name-nondirectory buffer-file-name))))
      (setq git-praise-proc
            (apply 'start-process
                   "git-praise" praise-buf
                   "git" "praise"
                   args))
      (with-current-buffer praise-buf
        (erase-buffer)
        (make-local-variable 'git-praise-file)
        (make-local-variable 'git-praise-current)
        (setq git-praise-file display-buf)
        (setq git-praise-current nil))
      (set-process-filter git-praise-proc 'git-praise-filter)
      (set-process-sentinel git-praise-proc 'git-praise-sentinel)
      (process-send-region git-praise-proc (point-min) (point-max))
      (process-send-eof git-praise-proc))))

(defun remove-git-praise-text-properties (start end)
  (let ((modified (buffer-modified-p))
        (inhibit-read-only t))
    (remove-text-properties start end '(point-entered nil))
    (set-buffer-modified-p modified)))

(defun git-praise-cleanup ()
  "Remove all praise properties"
    (mapc 'delete-overlay git-praise-overlays)
    (setq git-praise-overlays nil)
    (remove-git-praise-text-properties (point-min) (point-max)))

(defun git-praise-update-region (start end)
  "Rerun praise to get updates between START and END"
  (let ((overlays (overlays-in start end)))
    (while overlays
      (let ((overlay (pop overlays)))
        (if (< (overlay-start overlay) start)
            (setq start (overlay-start overlay)))
        (if (> (overlay-end overlay) end)
            (setq end (overlay-end overlay)))
        (setq git-praise-overlays (delete overlay git-praise-overlays))
        (delete-overlay overlay))))
  (remove-git-praise-text-properties start end)
  ;; We can be sure that start and end are at line breaks
  (git-praise-run (1+ (count-lines (point-min) start))
                 (count-lines (point-min) end)))

(defun git-praise-sentinel (proc status)
  (with-current-buffer (process-buffer proc)
    (with-current-buffer git-praise-file
      (setq git-praise-proc nil)
      (if git-praise-update-queue
          (git-praise-delayed-update))))
  ;;(kill-buffer (process-buffer proc))
  ;;(message "git praise finished")
  )

(defvar in-praise-filter nil)

(defun git-praise-filter (proc str)
  (with-current-buffer (process-buffer proc)
    (save-excursion
      (goto-char (process-mark proc))
      (insert-before-markers str)
      (goto-char (point-min))
      (unless in-praise-filter
        (let ((more t)
              (in-praise-filter t))
          (while more
            (setq more (git-praise-parse))))))))

(defun git-praise-parse ()
  (cond ((looking-at "\\([0-9a-f]\\{40\\}\\) \\([0-9]+\\) \\([0-9]+\\) \\([0-9]+\\)\n")
         (let ((hash (match-string 1))
               (src-line (string-to-number (match-string 2)))
               (res-line (string-to-number (match-string 3)))
               (num-lines (string-to-number (match-string 4))))
           (delete-region (point) (match-end 0))
           (setq git-praise-current (list (git-praise-new-commit hash)
                                         src-line res-line num-lines)))
         t)
        ((looking-at "\\([a-z-]+\\) \\(.+\\)\n")
         (let ((key (match-string 1))
               (value (match-string 2)))
           (delete-region (point) (match-end 0))
           (git-praise-add-info (car git-praise-current) key value)
           (when (string= key "filename")
             (git-praise-create-overlay (car git-praise-current)
                                       (caddr git-praise-current)
                                       (cadddr git-praise-current))
             (setq git-praise-current nil)))
         t)
        (t
         nil)))

(defun git-praise-new-commit (hash)
  (with-current-buffer git-praise-file
    (or (gethash hash git-praise-cache)
        ;; Assign a random color to each new commit info
        ;; Take care not to select the same color multiple times
        (let* ((color (if git-praise-colors
                          (git-praise-random-pop git-praise-colors)
                        git-praise-ancient-color))
               (info `(,hash (color . ,color))))
          (puthash hash info git-praise-cache)
          info))))

(defun git-praise-create-overlay (info start-line num-lines)
  (with-current-buffer git-praise-file
    (save-excursion
      (let ((inhibit-point-motion-hooks t)
            (inhibit-modification-hooks t))
        (goto-char (point-min))
        (forward-line (1- start-line))
        (let* ((start (point))
               (end (progn (forward-line num-lines) (point)))
               (ovl (make-overlay start end))
               (hash (car info))
               (spec `((?h . ,(substring hash 0 6))
                       (?H . ,hash)
                       (?a . ,(git-praise-get-info info 'author))
                       (?A . ,(git-praise-get-info info 'author-mail))
                       (?c . ,(git-praise-get-info info 'committer))
                       (?C . ,(git-praise-get-info info 'committer-mail))
                       (?s . ,(git-praise-get-info info 'summary)))))
          (push ovl git-praise-overlays)
          (overlay-put ovl 'git-praise info)
          (overlay-put ovl 'help-echo
                       (format-spec git-praise-mouseover-format spec))
          (if git-praise-use-colors
              (overlay-put ovl 'face (list :background
                                           (cdr (assq 'color (cdr info))))))
          (overlay-put ovl 'line-prefix
                       (propertize (format-spec git-praise-prefix-format spec)
                                   'face 'git-praise-prefix-face)))))))

(defun git-praise-add-info (info key value)
  (nconc info (list (cons (intern key) value))))

(defun git-praise-get-info (info key)
  (cdr (assq key (cdr info))))

(defun git-praise-current-commit ()
  (let ((info (get-char-property (point) 'git-praise)))
    (if info
        (car info)
      (error "No commit info"))))

(defun git-describe-commit (hash)
  (with-temp-buffer
    (call-process "git" nil t nil
                  "log" "-1"
		  (concat "--pretty=" git-praise-log-oneline-format)
                  hash)
    (buffer-substring (point-min) (point-max))))

(defvar git-praise-last-identification nil)
(make-variable-buffer-local 'git-praise-last-identification)
(defun git-praise-identify (&optional hash)
  (interactive)
  (let ((info (gethash (or hash (git-praise-current-commit)) git-praise-cache)))
    (when (and info (not (eq info git-praise-last-identification)))
      (message "%s" (nth 4 info))
      (setq git-praise-last-identification info))))

;; (defun git-praise-after-save ()
;;   (when git-praise-mode
;;     (git-praise-cleanup)
;;     (git-praise-run)))
;; (add-hook 'after-save-hook 'git-praise-after-save)

(defun git-praise-after-change (start end length)
  (when git-praise-mode
    (git-praise-enq-update start end)))

(defvar git-praise-last-update nil)
(make-variable-buffer-local 'git-praise-last-update)
(defun git-praise-enq-update (start end)
  "Mark the region between START and END as needing praise update"
  ;; Try to be smart and avoid multiple callouts for sequential
  ;; editing
  (cond ((and git-praise-last-update
              (= start (cdr git-praise-last-update)))
         (setcdr git-praise-last-update end))
        ((and git-praise-last-update
              (= end (car git-praise-last-update)))
         (setcar git-praise-last-update start))
        (t
         (setq git-praise-last-update (cons start end))
         (setq git-praise-update-queue (nconc git-praise-update-queue
                                             (list git-praise-last-update)))))
  (unless (or git-praise-proc git-praise-idle-timer)
    (setq git-praise-idle-timer
          (run-with-idle-timer 0.5 nil 'git-praise-delayed-update))))

(defun git-praise-delayed-update ()
  (setq git-praise-idle-timer nil)
  (if git-praise-update-queue
      (let ((first (pop git-praise-update-queue))
            (inhibit-point-motion-hooks t))
        (git-praise-update-region (car first) (cdr first)))))

(provide 'git-praise)

;;; git-praise.el ends here
