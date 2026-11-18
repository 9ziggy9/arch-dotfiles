;;; universal.el --- keys that work everywhere -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))
(require 'ui (locate-user-emacs-file "ui"))  ; my/mix, my/scheme-color

(defun univ/spawn-window ()
  "Split to the right, showing the current buffer in the new window too."
  (interactive)
  (select-window (split-window-right)))

;; Zoom: text size, or in a PDF, the page
(defun univ/zoom-in ()
  "Make the text bigger, or zoom into the PDF."
  (interactive)
  (if (derived-mode-p 'pdf-view-mode)
      (pdf-view-enlarge pdf-view-resize-factor)
    (text-scale-increase 1)))

(defun univ/zoom-out ()
  "Make the text smaller, or zoom out of the PDF."
  (interactive)
  (if (derived-mode-p 'pdf-view-mode)
      (pdf-view-shrink pdf-view-resize-factor)
    (text-scale-decrease 1)))

(defun univ/zoom-reset ()
  "Reset text scale in the current buffer, or fit the PDF to the width."
  (interactive)
  (if (derived-mode-p 'pdf-view-mode)
      (pdf-view-fit-width-to-window)
    (text-scale-set 0)))

(defun univ/outside-minibuffer (command)
  "A binding for COMMAND that steps aside while completing.
That is, in the minibuffer and while an autocompletion popup is up,
so keys like C-j/C-k move through candidates there instead."
  `(menu-item "" ,command
              :filter ,(lambda (cmd)
                         (unless (or (minibufferp)
                                     (bound-and-true-p completion-in-region-mode))
                           cmd))))

(defun univ/in-file-buffer (command)
  "A binding for COMMAND only in buffers visiting a file, and treemacs.
Anywhere else (popups, the minibuffer, *scratch*...) the key falls
through to its usual binding."
  `(menu-item "" ,command
              :filter ,(lambda (cmd)
                         (when (or buffer-file-name
                                   (derived-mode-p 'treemacs-mode))
                           cmd))))

(defun univ/toggle-treemacs ()
  "Show this file's project in treemacs, or hide treemacs if it's showing.
From a popup, the popup closes and this acts on the main frame."
  (interactive)
  (require 'treemacs)
  (pop/leave)
  (with-current-buffer (window-buffer (selected-window))
    (cond ((eq (treemacs-current-visibility) 'visible)
           ;; peeking ends on leaving treemacs, which this skips
           (when (bound-and-true-p treemacs-peek-mode) (treemacs-peek-mode -1))
           (delete-window (treemacs-get-local-window)))
          ((not buffer-file-name)
           (user-error "Treemacs opens from a buffer visiting a file"))
          (t
           (treemacs-add-and-display-current-project-exclusively)))))

;; Buffer cycling skips anything not visiting a file (compilation,
;; dired, *Warnings*...), so it only steps through your code
(defun univ/skip-non-file-buffer (_window buffer _bury-or-kill)
  (not (buffer-file-name buffer)))

(defun univ/previous-file-buffer ()
  "Switch to the previous buffer that visits a file."
  (interactive)
  (let ((switch-to-prev-buffer-skip #'univ/skip-non-file-buffer))
    (previous-buffer)))

(defun univ/next-file-buffer ()
  "Switch to the next buffer that visits a file."
  (interactive)
  (let ((switch-to-prev-buffer-skip #'univ/skip-non-file-buffer))
    (next-buffer)))

;; Fullscreen, tiling-WM style: the window takes the whole frame (treemacs
;; too), and toggling again puts the old layout back.  Whatever you did in
;; the window meanwhile (moving point, switching buffer) carries over.

(defun univ/toggle-fullscreen-window ()
  "Make the selected window fill the frame, or restore the previous layout."
  (interactive)
  (let ((saved (frame-parameter nil 'univ/fullscreen-config)))
    (cond (saved
           (let ((buf (current-buffer))
                 (pt (point)))
             (set-frame-parameter nil 'univ/fullscreen-config nil)
             (set-window-configuration saved)
             (switch-to-buffer buf nil t)
             (goto-char pt)))
          ((one-window-p t)
           (message "Already the only window"))
          (t
           (set-frame-parameter nil 'univ/fullscreen-config
                                (current-window-configuration))
           (let ((ignore-window-parameters t)) ; side windows too
             (delete-other-windows))))))

(defun univ/resize-window (columns lines)
  "A command growing the window by COLUMNS and LINES (negative shrinks)."
  (lambda ()
    (interactive)
    (unless (zerop columns) (enlarge-window columns t))
    (unless (zerop lines) (enlarge-window lines))))

;; Tabs, like kitty and qutebrowser: M-1..M-9 go to tab N, or open a new
;; tab at the end with dired in the current buffer's directory if there is
;; no tab N (like i3's workspace keys); M-w closes the tab.  From a popup,
;; the popup closes and the key acts on the main frame.
(setq tab-bar-show 1                    ; the tab bar shows once there are 2+ tabs
      tab-bar-new-tab-to 'rightmost     ; new tabs at the end, so M-N counts from left
      tab-bar-tab-hints t               ; numbered tabs
      tab-bar-close-button-show nil
      tab-bar-new-button-show nil)

;; The tab bar looks like kitty's slanted powerline tabs, slim: every tab on
;; the scheme's first shade above the background (base01, like kitty's
;; inactive tabs) in its normal text, the selected one told apart by bold
;; text in the scheme's accent (its yellow); tabs are divided by a thin ╱
;; and the last ends in a slant.  Under tinty's scheme these are pairings
;; apply-scheme made readable; under any other theme, shades mixed from its
;; colors, with the text checked.  Recolored with every theme.

(defun univ/tab-name (tab i)
  "TAB, the I-th tab, drawn like a kitty powerline tab."
  (let* ((bar (face-background 'default nil t))
         (fg (face-foreground 'default nil t))
         (tinty (my/scheme-text :base0A))  ; nil under other themes
         (bg (if tinty (my/scheme-color :base01) (my/mix bar fg 0.12)))
         (text (if tinty (my/scheme-color :base05)
                 (my/readable (my/mix bar fg 0.6) bg)))
         (accent (or tinty (my/readable (or (my/scheme-color :base0A) fg) bg)))
         (current (eq (car tab) 'current-tab))
         (last (= i (length (funcall tab-bar-tabs-function))))  ; I counts from 1
         (name (truncate-string-to-width (alist-get 'name tab) 30 nil nil "…")))
    (concat
     (propertize (format " %d %s " i name)
                 'face (if current
                           `(:background ,bg :foreground ,accent :weight bold)
                         `(:background ,bg :foreground ,text)))
     (if last
         (propertize "" 'face `(:background ,bar :foreground ,bg))
       (propertize "╱" 'face `(:background ,bg :foreground ,bar))))))

(defun univ/tab-bar-face (&rest _)
  "The bar behind the tabs: the theme's background, a bit smaller than text."
  (set-face-attribute 'tab-bar nil
                      :background (face-background 'default nil t)
                      :foreground (face-foreground 'default nil t)
                      :box nil :height 0.6 :inherit 'unspecified))

(setq tab-bar-format '(tab-bar-format-tabs) ; just the tabs, no buttons
      tab-bar-separator ""                  ; univ/tab-name draws its own
      tab-bar-auto-width nil                ; tabs as wide as their names
      tab-bar-tab-name-format-function #'univ/tab-name)
(univ/tab-bar-face)
(add-hook 'enable-theme-functions #'univ/tab-bar-face)

(defun univ/tab-select-or-new (n)
  "Go to tab N, or open a new tab with dired in the current directory."
  (pop/leave)
  (if (<= n (length (tab-bar-tabs)))
      (tab-bar-select-tab n)
    (let ((dir (with-current-buffer (window-buffer (selected-window))
                 default-directory)))
      (tab-bar-new-tab)
      (dired dir))))

(defun univ/tab-close ()
  "Close the current tab."
  (interactive)
  (pop/leave)
  (if (cdr (tab-bar-tabs))
      (tab-bar-close-tab)
    (message "Only one tab")))

(defvar-keymap univ-search-map
  :doc "M-s: search."
  "M-f" #'find-file               ; open a file (any directory)
  "M-d" #'consult-line            ; text in this document
  "M-i" #'consult-imenu           ; search defined fns
  "M-I" #'consult-eglot-symbols   ; search project symbols
  "M-p" #'consult-ripgrep)        ; text anywhere in the project

(defvar-keymap univ-keys-map
  ;; Windows
  "C-h"   (univ/outside-minibuffer #'windmove-left)
  "C-j"   (univ/outside-minibuffer #'windmove-down)
  "C-k"   (univ/outside-minibuffer #'windmove-up)
  "C-l"   (univ/outside-minibuffer #'windmove-right)
  "C-S-h" #'windmove-swap-states-left
  "C-S-j" #'windmove-swap-states-down
  "C-S-k" #'windmove-swap-states-up
  "C-S-l" #'windmove-swap-states-right
  "C-]"   #'window-layout-transpose  ; side-by-side <-> stacked
  "C-f"   (univ/outside-minibuffer #'univ/toggle-fullscreen-window)
  "C-<right>" (univ/outside-minibuffer (univ/resize-window 4 0))
  "C-<left>"  (univ/outside-minibuffer (univ/resize-window -4 0))
  "C-<up>"    (univ/outside-minibuffer (univ/resize-window 0 2))
  "C-<down>"  (univ/outside-minibuffer (univ/resize-window 0 -2))
  ;; (not in the minibuffer, where there's no window of its own to close)
  "C-x"   (univ/outside-minibuffer #'pop/close-or-delete-window)
  ;; In treemacs, C-<return> opens the file at point in a split instead
  "C-<return>" `(menu-item "" univ/spawn-window
                           :filter ,(lambda (cmd)
                                      (unless (derived-mode-p 'treemacs-mode)
                                        cmd)))
  "C-t"   (univ/in-file-buffer #'univ/toggle-treemacs)
  ;; Buffers
  "C-,"   (univ/outside-minibuffer #'univ/previous-file-buffer)
  "C-."   (univ/outside-minibuffer #'univ/next-file-buffer)
  ;; Zoom
  "C-="   #'univ/zoom-in
  "C--"   #'univ/zoom-out
  "C-0"   #'univ/zoom-reset
  ;; Searching
  "M-s"   univ-search-map ; M-s M-f file, M-s M-d document, M-s M-p project
  )

;; Escape cancels any prompt immediately (popups handle it in popup.el)
;; Popups are on F-keys; see modeline.el
(keymap-set minibuffer-local-map "<escape>" #'abort-minibuffers)

(define-minor-mode univ-keys-mode
  "Global keys that take priority over all other keymaps."
  :global t
  :keymap univ-keys-map)

(univ-keys-mode 1)

;; Tab keys (above), set on the map here so reloading this file updates them
(dotimes (i 9)
  (let ((n (1+ i)))
    (keymap-set univ-keys-map (format "M-%d" n)
                (univ/outside-minibuffer
                 (lambda () (interactive) (univ/tab-select-or-new n))))))
(keymap-set univ-keys-map "M-w" (univ/outside-minibuffer #'univ/tab-close))
;; Jump hints, like qutebrowser's Alt+Space (avy, set up in editing.el)
(keymap-set univ-keys-map "M-SPC" (univ/outside-minibuffer #'avy-goto-word-0))

;; These keys must come before evil's in `emulation-mode-map-alists'.
;; Evil puts its own in front the first time it's turned on in a
;; buffer, so move ours back in front whenever it is; then it doesn't
;; matter whether this file loads before or after evil
(defvar univ-keys-alist `((univ-keys-mode . ,univ-keys-map)))

(defun univ/keys-first ()
  "Put the universal keys at the front of `emulation-mode-map-alists'."
  (setq emulation-mode-map-alists
        (cons univ-keys-alist (delq univ-keys-alist emulation-mode-map-alists))))

(univ/keys-first)
(add-hook 'evil-local-mode-hook #'univ/keys-first)

(provide 'universal)
