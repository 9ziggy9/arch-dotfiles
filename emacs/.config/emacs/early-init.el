;;; early-init.el --- -*- lexical-binding: t -*-

;; The font's size; its family is the one picked with font-select, read
;; from the theme file below (ui.el applies a new one)
(defvar my/font-size 12)

;; Set before the first frame exists: no bar flash, no font resize jump
(setq default-frame-alist
      `((menu-bar-lines . 0)
        (tool-bar-lines . 0)
        (vertical-scroll-bars)
        (font . ,(format "MesloLGS Nerd Font Mono-%s" my/font-size))))
(setq frame-inhibit-implied-resize t)

;; New frames open in the color scheme's background and text colors, and
;; the font, instead of flashing white until the theme is applied; they're
;; read from the theme file tinty writes (packages, and so the theme
;; itself, load later)
(ignore-errors
  (with-temp-buffer
    (insert-file-contents (locate-user-emacs-file "themes/base16-tinty-theme.el"))
    (dolist (attr '((:base00 . background-color) (:base05 . foreground-color)))
      (goto-char (point-min))
      (when (re-search-forward (format "%s \"\\(#[[:xdigit:]]\\{6\\}\\)\"" (car attr)) nil t)
        (push (cons (cdr attr) (match-string 1)) default-frame-alist)))
    (goto-char (point-min))
    (when (re-search-forward "(setq base16-tinty-font \"\\([^\"]+\\)\")" nil t)
      (setf (alist-get 'font default-frame-alist)
            (format "%s-%s" (match-string 1) my/font-size)))))

;; Fewer garbage collections during startup, restored afterward
(setq gc-cons-threshold most-positive-fixnum)
(add-hook 'emacs-startup-hook
          (lambda () (setq gc-cons-threshold (* 16 1024 1024))))

(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                         ("gnu"   . "https://elpa.gnu.org/packages/"))
      load-prefer-newer t
      warning-suppress-types '((files missing-lexbind-cookie))
      native-comp-async-report-warnings-errors 'silent)
