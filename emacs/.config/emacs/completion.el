;;; completion.el --- minibuffer completion, M-x, autocompletion -*- lexical-binding: t -*-

;;; Completion: fzf-style fuzzy finding in the minibuffer
(use-package vertico              ; vertical candidate list
  :init (vertico-mode 1)
  :custom (vertico-cycle t)
  :bind (:map vertico-map
         ("C-j" . vertico-next)
         ("C-k" . vertico-previous)))

;; Rows like rofi's: every other one on a shade of its own, and the
;; selected one in the scheme's yellow (colors set with the other faces,
;; in ui.el).  Stripes are counted from the top of the list, so they stay
;; put as it scrolls.
(defface my/vertico-stripe '((t :extend t))
  "Background of every other row in vertico's list.")

(defun my/vertico-stripe (format cand prefix suffix index start)
  "Vertico's row for CAND, striped if it's an odd row from the top."
  (let ((row (funcall format cand prefix suffix index start)))
    (if (= index vertico--index)
        ;; the selected row's colors over everything on it, matches
        ;; included, so its text always reads on the yellow
        (add-face-text-property 0 (length row) 'vertico-current nil row)
      (when (= 1 (% (- index start) 2))
        (add-face-text-property 0 (length row) 'my/vertico-stripe 'append row)))
    row))

(advice-add 'vertico--format-candidate :around #'my/vertico-stripe)

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

;;; M-x lists only commands that make sense in the current buffer
;;; (commands written for other modes are left out); M-X narrows that
;;; further, to commands for the buffer's own modes.  marginalia shows
;;; each command's key beside it.
(setq read-extended-command-predicate #'command-completion-default-include-p)

;;; Autocompletion: a popup of candidates as you type (its text size is
;;; set with the other faces, in ui.el)
(use-package corfu
  :init (global-corfu-mode 1)
  :custom
  (corfu-auto t)             ; show candidates automatically while typing
  (corfu-auto-prefix 2)      ; ...after 2 characters
  (corfu-auto-delay 0.4)     ; ...and a short pause
  (corfu-cycle t))           ; wrap around at the ends of the list

(provide 'completion)
