;;; ui.el --- looks, windows, file and buffer browsing, popups -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))

;; Line numbers
(setq display-line-numbers-type 'relative)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;; A cursor only in the selected window, none in the other splits
(setq-default cursor-in-non-selected-windows nil)

;; Long messages show only their first line, rather than growing the echo area
(setq message-truncate-lines t)

;;; Theme

;; The colors are the color scheme that tinty applies to every program
;; (theme-select, $mod+Shift+t).  It writes the scheme for emacs as the theme
;; base16-tinty, themes/base16-tinty-theme.el, drawn by the base16-theme
;; package, and reloads it in a running daemon (`my/tinty-reload').

(require 'color)
(require 'cl-lib)

(defun my/mix (a b frac)
  "Color A with FRAC of color B mixed in."
  (apply #'color-rgb-to-hex
         (append (color-blend (color-name-to-rgb b) (color-name-to-rgb a) frac)
                 '(2))))

(defun my/contrast (a b)
  "The WCAG contrast ratio of colors A and B (1 to 21)."
  (let ((l (lambda (c)
             (apply #'+ (cl-mapcar
                         (lambda (w x) (* w (if (<= x 0.04045) (/ x 12.92)
                                              (expt (/ (+ x 0.055) 1.055) 2.4))))
                         '(0.2126 0.7152 0.0722) (color-name-to-rgb c))))))
    (let ((la (funcall l a)) (lb (funcall l b)))
      (/ (+ (max la lb) 0.05) (+ (min la lb) 0.05)))))

(defun my/readable (fg bg)
  "FG if it reads on BG (4.5:1, like apply-scheme's rule), else black or
white, whichever reads better."
  (if (or (not (color-defined-p fg)) (not (color-defined-p bg))
          (>= (my/contrast fg bg) 4.5))
      fg
    (if (> (my/contrast "#000000" bg) (my/contrast "#ffffff" bg)) "#000000" "#ffffff")))

(defun my/scheme-color (key &optional theme)
  "Color KEY (:base00 .. :base0F) of THEME's scheme (default: the current
theme), or nil when it isn't a base16 theme."
  (let* ((theme (or theme (car custom-enabled-themes)))
         (var (and theme (intern-soft (format "%s-theme-colors" theme)))))
    (and var (boundp var) (plist-get (symbol-value var) key))))

;; Face tweaks that hold in every scheme.  Faces set in the `user' theme win
;; over the loaded theme and only replace the attributes given, so these
;; survive scheme switches without being redone.
(custom-theme-set-faces
 'user
 '(line-number              ((t :height 0.72)))
 ;; the current line's number: bold, in the scheme's green (below), the same
 ;; size (it inherits the height) and not highlighted
 '(line-number-current-line ((t :inherit line-number :weight bold)))
 '(corfu-default      ((t :height 0.75)))  ; completion popup text
 ;; org: bigger headings, the folded-heading ellipsis without an underline
 '(org-document-title ((t :height 1.5 :weight bold)))
 '(org-level-1 ((t :height 1.3 :weight bold)))
 '(org-level-2 ((t :height 1.15 :weight bold)))
 '(org-level-3 ((t :height 1.05 :weight bold)))
 '(org-ellipsis ((t :underline nil))))

(use-package base16-theme
  :demand t
  :init
  ;; The line-number margin and fringe on the normal background, not a
  ;; separate shade (set before the theme loads below)
  (setq base16-theme-distinct-fringe-background nil))

;; tinty's theme file; Solarized Dark until a scheme has been applied
(setq custom-theme-directory (locate-user-emacs-file "themes/"))
(if (file-exists-p (expand-file-name "base16-tinty-theme.el" custom-theme-directory))
    (load-theme 'base16-tinty t)
  (load-theme 'base16-solarized-dark t))

(defun my/tinty-reload ()
  "Load the scheme tinty just wrote (run when the theme file changes).
A daemon's own frame is a hidden terminal one, where the theme hooks that
read colors from the frame see none, so the theme is loaded in an open
emacs window when there is one; with none open, emacs works those colors
out again in its next window (`my/recolor-new-frame')."
  (interactive)
  (let ((gui (seq-find #'display-graphic-p (frame-list))))
    (with-selected-frame (or gui (selected-frame))
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme 'base16-tinty t)))
  ;; frames made from now on open in the new colors (see early-init.el)
  (setf (alist-get 'background-color default-frame-alist) (my/scheme-color :base00)
        (alist-get 'foreground-color default-frame-alist) (my/scheme-color :base05))
  nil)

;; Every emacs (the daemon, or one started on its own) watches the theme
;; file, so a scheme picked with theme-select shows at once, everywhere
(require 'filenotify)

(defvar my/tinty-reload-timer nil)

(defun my/tinty-file-changed (event)
  "Reload the theme once tinty has finished writing it (EVENT is a
file-notify event in its directory)."
  (pcase-let ((`(,_ ,action ,file ,new-name) event))
    (when (and (memq action '(created changed renamed))
               (equal (file-name-nondirectory (or new-name file))
                      "base16-tinty-theme.el"))
      ;; one write can come as several events: reload after the last
      (when (timerp my/tinty-reload-timer)
        (cancel-timer my/tinty-reload-timer))
      (setq my/tinty-reload-timer
            (run-with-timer 0.3 nil
                            (lambda ()
                              (with-demoted-errors "Reloading the theme: %S"
                                (my/tinty-reload))))))))

(make-directory custom-theme-directory t)
(with-demoted-errors "Watching the theme file: %S"
  (file-notify-add-watch custom-theme-directory '(change)
                         #'my/tinty-file-changed))

;; The scheme's accent (its yellow) on the jump labels (avy, M-SPC), one
;; color for every label like qutebrowser's hints; the current line's
;; number in its green, on the line numbers' own background; and the
;; popup's border in its orange
(defun my/scheme-faces (&optional theme)
  (when-let* ((orange (my/scheme-color :base09 theme)))
    (setq pop/border-color orange)
    (when (frame-live-p pop/frame)
      (set-face-background 'child-frame-border orange pop/frame)))
  (let ((accent (my/scheme-color :base0A theme))
        (text (or (plist-get (bound-and-true-p base16-tinty-theme-text-on) :base0A)
                  (my/scheme-color :base00 theme))))
    (when (and accent text)
      (dolist (face '(avy-lead-face avy-lead-face-0 avy-lead-face-1 avy-lead-face-2))
        (face-spec-set face `((t :background ,accent :foreground ,text :weight bold))))))
  (set-face-attribute 'line-number-current-line nil
                      :foreground (or (my/scheme-color :base0B theme) 'unspecified)
                      :background 'unspecified))

(my/scheme-faces)
(add-hook 'enable-theme-functions #'my/scheme-faces)

;; A daemon loads the theme before any graphical frame exists, so the
;; colors worked out from it (window borders, tab bar, mode line) come out
;; wrong; work them out again in each new frame
(defun my/recolor-new-frame ()
  (when-let* ((theme (car custom-enabled-themes)))
    (run-hook-with-args 'enable-theme-functions theme)))

(add-hook 'server-after-make-frame-hook #'my/recolor-new-frame)

;;; Windows
(use-package window
  :ensure nil
  :custom
  (window-combination-resize t))

;; Borders between windows (turned on by mini-echo, see modeline.el), the
;; background with a quarter of the text color mixed in, so they show in
;; every theme (some, like the doom ones, hide the default border); redone
;; after each theme, since the color depends on it
(defun my/divider-faces (&rest _)
  "Color the window borders from the current theme's colors."
  (let ((bg (face-background 'default nil t))
        (fg (face-foreground 'default nil t)))
    (when (and (color-defined-p bg) (color-defined-p fg))
      (let ((line (my/mix bg fg 0.25)))
        (dolist (face '(window-divider window-divider-first-pixel
                        window-divider-last-pixel vertical-border))
          (set-face-attribute face nil :foreground line :background line))))))

(my/divider-faces)
(add-hook 'enable-theme-functions #'my/divider-faces)

;;; Key hints: pause after a prefix to see what can follow it
(use-package which-key
  :ensure nil                          ; built in since Emacs 30
  :init (which-key-mode 1))

;;; Richer help buffers (source, references, keybindings)
(use-package helpful
  :bind
  (([remap describe-function] . helpful-callable)
   ([remap describe-variable] . helpful-variable)
   ([remap describe-command]  . helpful-command)
   ([remap describe-key]      . helpful-key)
   ([remap describe-symbol]   . helpful-symbol)))

;;; Command log: a live side buffer of every key and the command it ran
(use-package command-log-mode
  :commands clm/toggle-command-log-buffer
  :custom
  (command-log-mode-key-binding-open-log nil)   ; don't grab C-c o
  (command-log-mode-open-log-turns-on-mode t)   ; opening the log starts logging
  (command-log-mode-is-global t))               ; ...in every buffer

;;; File tree: C-t (see universal.el)
(use-package treemacs
  :defer t
  :hook
  (treemacs-mode . (lambda ()        ; text at 75%
                     (face-remap-add-relative 'default :height 0.75)))
  (treemacs-mode . my/treemacs-peek-setup)
  :bind (:map treemacs-mode-map
         ;; open the file at point in a split beside the window you came from
         ("C-<return>" . treemacs-visit-node-horizontal-split))
  :custom
  (treemacs-no-png-images t)         ; no icons, just +/- on directories
  (treemacs-width 22)                ; columns (default 35)
  :config
  (treemacs-follow-mode 1)           ; highlight the file you're in
  (treemacs-project-follow-mode 1))  ; switch projects as you do

;; Resting on a file shows it in the window you came from; files opened
;; only for that are closed again when you leave treemacs.  Peek mode ends
;; itself on leaving treemacs, so it's turned on again on every visit.
(defun my/treemacs-peek-on-enter (window)
  (when (and (eq window (selected-window)) (not treemacs-peek-mode))
    (treemacs-peek-mode 1)))

(defun my/treemacs-peek-setup ()
  (add-hook 'window-selection-change-functions #'my/treemacs-peek-on-enter nil t))

(use-package treemacs-evil           ; j/k and friends inside treemacs
  :after (treemacs evil))

;;; Dired
(use-package dired
  :ensure nil
  :custom
  (dired-kill-when-opening-new-dired-buffer t)
  :init
  ;; After evil-collection's own dired keys, so these win
  (add-hook 'evil-collection-setup-hook
            (lambda (mode _keymaps)
              (when (eq mode 'dired)
                (evil-define-key 'normal dired-mode-map
                  "=" #'dired-create-empty-file   ; the +/= key on its own
                  "+" #'dired-create-directory))))) ; with Shift

(defun pop/dired-here ()
  "A dired buffer at the main buffer's directory, on the file you came from."
  (let* ((main (pop/main-buffer))
         (file (buffer-file-name main))
         (buf (dired-noselect (buffer-local-value 'default-directory main))))
    (when file
      (with-current-buffer buf (dired-goto-file file)))
    buf))

(defun pop/dired-find-file ()
  "Enter directories in place; open files in the main frame."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (if (file-directory-p file)
        (dired-find-file)
      (pop/hide)
      (find-file file))))

(defun pop/dired-open-in-split ()
  "Hide the popup and open the file at point in a new split in the main frame."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (pop/hide)
    (select-window (split-window-right))
    (find-file file)))

(pop/define dired
  :match   (derived-mode-p 'dired-mode)
  :open    #'pop/dired-here
  :size    (0.8 . 0.8)
  :setup   (pop/text-scale 0.8)
  :keys    ("RET"        pop/dired-find-file
            "C-<return>" pop/dired-open-in-split
            "q"          pop/hide)
  :hints   ("C-RET" "split"  "-" "up"  "m/u" "mark"
            "d/x" "delete"  "R" "rename"  "C" "copy"  "=" "file"  "+" "dir"
            "?" "keys"))

;;; Ibuffer
(use-package ibuffer
  :ensure nil
  :custom
  (ibuffer-expert t)
  (ibuffer-show-empty-filter-groups nil))

(use-package ibuffer-project            ; group buffers by project
  :hook
  (ibuffer . (lambda ()
               (setq ibuffer-filter-groups (ibuffer-project-generate-filter-groups)))))

(defun pop/ibuffer-here ()
  "A fresh ibuffer list, with the cursor on the buffer you came from."
  (let ((main (pop/main-buffer)))
    (save-window-excursion (ibuffer nil "*Ibuffer*" nil t))
    (with-current-buffer "*Ibuffer*"
      (ibuffer-update nil t)
      (ignore-errors (ibuffer-jump-to-buffer (buffer-name main)))
      (current-buffer))))

(defun pop/ibuffer-visit ()
  "Hide the popup and show the buffer at point in the main window."
  (interactive)
  (let ((buf (ibuffer-current-buffer t)))
    (pop/hide)
    (switch-to-buffer buf)))

(defun pop/ibuffer-visit-in-split ()
  "Hide the popup and show the buffer at point in a new split."
  (interactive)
  (let ((buf (ibuffer-current-buffer t)))
    (pop/hide)
    (select-window (split-window-right))
    (switch-to-buffer buf)))

(pop/define ibuffer
  :match   (derived-mode-p 'ibuffer-mode)
  :open    #'pop/ibuffer-here
  :setup   (pop/text-scale 0.8)
  :keys    ("RET"        pop/ibuffer-visit
            "C-<return>" pop/ibuffer-visit-in-split
            "q"          pop/hide)
  :hints   ("C-RET" "split"  "m/u" "mark"  "d/x" "kill"
            "S" "save"  "TAB" "next group"
            "?" "keys"))

;;; Scratchpad

;; The *scratch* buffer, for notes and trying out elisp; escape leaves
;; insert state first, then closes

(pop/define scratch
  :match (equal (buffer-name) "*scratch*")
  :open  #'get-scratch-buffer-create)

;;; About

;; This config's own README.org, read-only in a popup with no mode line.
;; It's a copy, refreshed on each open, so the file itself stays a normal
;; buffer wherever you edit it.

(defun pop/about-buffer ()
  "A read-only copy of the config's README.org."
  (let ((file (locate-user-emacs-file "README.org")))
    (with-current-buffer (get-buffer-create "*about*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if (file-exists-p file)
            (insert-file-contents file)
          (insert (format "No %s yet." (abbreviate-file-name file))))
        (unless (derived-mode-p 'org-mode)
          (org-mode))
        (goto-char (point-min)))
      (setq buffer-read-only t)
      (current-buffer))))

(pop/define about
  :match (equal (buffer-name) "*about*")
  :open  #'pop/about-buffer
  :setup (progn (pop/text-scale 0.8)
                (visual-line-mode 1))   ; wrap long lines, don't cut them off
  :keys  ("q" pop/hide))

(provide 'ui)
