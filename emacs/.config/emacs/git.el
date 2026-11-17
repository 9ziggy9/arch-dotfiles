;;; git.el --- magit, and GitHub through forge -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))

;;; Magit

;; The status buffer takes the whole frame, not a popup; q (or the git
;; slot again) puts the old layout back.  Evil keys come from
;; evil-collection (see editing.el).  Cloning: M-x magit-clone takes
;; owner/name, or just name for your own GitHub repos.
(use-package magit
  :commands (magit-status magit-mode-bury-buffer)
  :custom
  (magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1)
  (magit-bury-buffer-function #'magit-restore-window-configuration))

(defun my/git-toggle ()
  "Open magit's status for this repo, or close it if it's showing.
From a popup, the popup closes and this acts on the main frame."
  (interactive)
  (pop/leave)
  (with-current-buffer (window-buffer (selected-window))
    (if (derived-mode-p 'magit-mode)
        (magit-mode-bury-buffer)
      (call-interactively #'magit-status))))

;;; GitHub

;; forge: pull requests, issues and the repo's GitHub page from inside
;; magit; its menu is N in a magit buffer (pull requests and issues show
;; in the status buffer once the repo is added there).  It needs a GitHub
;; token in ~/.authinfo; see forge's manual, "Setup for Github".
(use-package forge
  :after magit)

;; Making a GitHub repo from this one isn't something forge does, so that
;; runs gh; its output goes to *gh*, shown if it fails
(defun my/gh-repo-create (name visibility description)
  "Create the GitHub repo NAME for this repo, as its origin, and push.
VISIBILITY is \"private\" or \"public\"."
  (interactive
   (let ((root (progn (require 'magit)
                      (or (magit-toplevel) (user-error "Not in a git repo")))))
     (when (magit-get "remote.origin.url")
       (user-error "This repo already has an origin: %s"
                   (magit-get "remote.origin.url")))
     (list (read-string "Repo name: "
                        (file-name-nondirectory (directory-file-name root)))
           (completing-read "Visibility: " '("private" "public") nil t
                            nil nil "private")
           (read-string "Description (optional): "))))
  (let ((root (magit-toplevel)))
    (make-process
     :name "gh" :buffer "*gh*" :connection-type 'pipe
     :command `("gh" "repo" "create" ,name ,(concat "--" visibility)
                "--source" ,root "--remote" "origin"
                ,@(unless (string-empty-p description)
                    (list "--description" description))
                ;; pushing needs a commit to push
                ,@(when (magit-rev-verify "HEAD") '("--push")))
     :sentinel (lambda (proc _)
                 (unless (process-live-p proc)
                   (if (zerop (process-exit-status proc))
                       (progn (message "Created %s on GitHub" name)
                              (magit-refresh-all))
                     (display-buffer "*gh*")))))))

(provide 'git)
