;;; completion.el --- minibuffer completion, M-x, autocompletion -*- lexical-binding: t -*-

;;; Completion: fzf-style fuzzy finding in the minibuffer
(use-package vertico              ; vertical candidate list
  :init (vertico-mode 1)
  :custom (vertico-cycle t)
  :bind (:map vertico-map
         ("C-j" . vertico-next)
         ("C-k" . vertico-previous)))

(use-package orderless            ; fzf-like matching
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion))))
  ;; Each space-separated term matches literally, as a regexp, or
  ;; fuzzily (letters in order, like fzf); terms can come in any order
  (orderless-matching-styles '(orderless-literal orderless-regexp orderless-flex)))

(use-package consult              ; buffer switcher and searches
  :init
  (recentf-mode 1))               ; lets consult-buffer offer recent files too

(use-package marginalia           ; a description beside each candidate
  :init (marginalia-mode 1))

;;; M-x: a centered box, bordered like the popups, at 75% text.  M-x
;;; lists only commands that make sense in the current buffer (commands
;;; written for other modes are left out); M-X narrows that further, to
;;; commands for the buffer's own modes.  marginalia shows each command's
;;; key beside it.
(setq read-extended-command-predicate #'command-completion-default-include-p)

(use-package vertico-posframe
  :custom
  (vertico-posframe-border-width 3)
  :custom-face
  (vertico-posframe-border ((t (:background "#cc7833"))))) ; popup orange

(use-package vertico-multiform    ; per-command looks, part of vertico
  :ensure nil
  :after vertico
  :custom
  (vertico-multiform-commands
   (let ((box '(posframe (vertico-count . 16) (vertico-posframe-min-height . 16))))
     `((execute-extended-command ,@box)
       (execute-extended-command-for-buffer ,@box))))
  :config
  (vertico-multiform-mode 1))

(defun my/mx-text-size ()
  "M-x's text at 75%."
  (when (memq current-minibuffer-command
              '(execute-extended-command execute-extended-command-for-buffer))
    (face-remap-add-relative 'default :height 0.75)))

(add-hook 'minibuffer-setup-hook #'my/mx-text-size)

;;; Autocompletion: a popup of candidates as you type (its text size is
;;; set with the other faces, in ui.el)
(use-package corfu
  :init (global-corfu-mode 1)
  :custom
  (corfu-auto t)             ; show candidates automatically while typing
  (corfu-auto-prefix 2)      ; ...after 3 characters
  (corfu-auto-delay 0.4)     ; ...and a short pause
  (corfu-cycle t))           ; wrap around at the ends of the list

(provide 'completion)
