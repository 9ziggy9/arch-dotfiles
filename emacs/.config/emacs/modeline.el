;;; modeline.el --- the bottom bar and its F-key slots -*- lexical-binding: t -*-

;; Windows have no mode lines of their own.  The echo area line at the
;; bottom of the frame (mini-echo) is the bar for the window you're in: its
;; buffer name on the left, messages after it, and on the right
;; diagnostics, line:column and numbered slots (slot N being F<N>).  A
;; message too long for the room between is cut short, so it never covers
;; the rest.  Popups show none of it.  Each major mode can declare its
;; own slots in `ml/mode-slots'; any other mode gets `ml/default-slots'.
;; F-keys follow the buffer you're working in, even while a popup has
;; focus, so pressing a popup's key again hides it.  F-keys with no slot
;; keep their usual binding (e.g. F11 fullscreen).

(require 'cl-lib)
(require 'popup (locate-user-emacs-file "popup"))
(require 'universal (locate-user-emacs-file "universal"))
(require 'ui (locate-user-emacs-file "ui"))  ; my/scheme-color, my/mix, my/readable

;;;; Slots

(defvar ml/default-slots
  '(("compile" . pop/compile-toggle)
    ("dired"   . pop/dired-toggle)
    ("ibuffer" . pop/ibuffer-toggle)
    ("git"     . my/git-toggle)
    ("about"   . pop/about-toggle))
  "Slots (LABEL . COMMAND) for modes without their own; the first is F1.
A nil entry leaves that slot empty.")

(defvar ml/mode-slots nil
  "Alist of (MODE . SLOTS); the first MODE the buffer derives from wins.
Its SLOTS replace `ml/default-slots', e.g.

  (add-to-list \\='ml/mode-slots
               `(c-ts-mode ,@ml/default-slots (\"format\" . eglot-format)))")

(defun ml/slots (&optional buffer)
  "The slots for BUFFER (default: the current buffer)."
  (with-current-buffer (or buffer (current-buffer))
    (or (cdr (cl-find-if (lambda (entry) (derived-mode-p (car entry)))
                         ml/mode-slots))
        ml/default-slots)))

(defun ml/slot-command (n)
  "The command in slot N (1-based) for the buffer you're working in."
  (cdr (nth (1- n) (ml/slots (pop/main-buffer)))))

;; F1..F12 run their slot; an empty slot makes the binding vanish, so the
;; key falls through to whatever it normally does
(dotimes (i 12)
  (let ((n (1+ i)))
    (keymap-set univ-keys-map (format "<f%d>" n)
                `(menu-item "" ignore
                            :filter ,(lambda (_) (ml/slot-command n))))))

;; Popups are isolated from the universal keys; let the F-keys through
(setq pop/always-keep
      (append pop/always-keep
              (cl-loop for n from 1 to 12 collect (format "<f%d>" n))))
(pop/reset-keys)

;;;; Colors

;; The bar is drawn in the mode-line face.  base16 themes make it base04
;; text on base02, which in some schemes (atelier-sulphurpool: 1.7:1
;; contrast) is barely readable; use the scheme's normal text (base05) on
;; its second-darkest shade (base01) instead.
(defun ml/base16-mode-line (&optional theme)
  "Readable mode-line colors when THEME is a base16 scheme."
  (when (and theme (string-prefix-p "base16-" (symbol-name theme)))
    (when-let* ((bg (my/scheme-color :base01 theme))
                (fg (my/scheme-color :base05 theme)))
      (set-face-attribute 'mode-line nil :background bg :foreground fg))))

(dolist (theme custom-enabled-themes)
  (ml/base16-mode-line theme))
;; Early (-50), so the segments below are colored from these
(add-hook 'enable-theme-functions #'ml/base16-mode-line -50)

;; Segments, like the i3 status bar: they alternate between the bar's own
;; colors and a lighter shade with brighter text.  Under tinty's scheme the
;; shade is the bar's own second one (base02, with base06 text), a pairing
;; apply-scheme made readable; under any other theme it's 30% of the way
;; to the text color, worked out from the theme's mode line.
(defface ml/seg-a '((t)) "Segment in the bar's own colors.")
(defface ml/seg-b '((t)) "Segment in the lighter shade.")

(defun ml/update-segment-faces (&rest _)
  "Color the segments from the current theme's mode line."
  ;; (some themes, like doom-nord, leave the mode line's text color unset)
  (let ((bg (face-background 'mode-line nil 'default))
        (fg (face-foreground 'mode-line nil 'default)))
    (when (and bg fg (color-defined-p bg) (color-defined-p fg))
      (set-face-attribute 'ml/seg-a nil :background bg :foreground (my/readable fg bg))
      (if (my/scheme-text-on :base02)   ; tinty's scheme
          (set-face-attribute 'ml/seg-b nil
                              :background (my/scheme-color :base02)
                              :foreground (my/scheme-color :base06))
        (let ((shade (my/mix bg fg 0.3)))
          (set-face-attribute 'ml/seg-b nil
                              :background shade
                              ;; always readable, whatever the shade (ui.el)
                              :foreground (my/readable
                                           (my/mix fg (if (color-dark-p (color-name-to-rgb bg))
                                                          "#ffffff" "#000000")
                                                   0.5)
                                           shade)))))))

(ml/update-segment-faces)
(add-hook 'enable-theme-functions #'ml/update-segment-faces)

;;;; What the bar shows

;; The name stands out in bold white (black where white wouldn't read, as on
;; a light scheme), on a shade slightly lighter than the bar; redone after
;; each theme
(defface ml/name '((t :weight bold :foreground "#ffffff"))
  "The buffer-name segment.")

(defun ml/update-name-face (&rest _)
  "Shade the name's segment from the bar's colors."
  (let ((bg (face-background 'mode-line nil 'default))
        (fg (face-foreground 'mode-line nil 'default)))
    (if (and (color-defined-p bg) (color-defined-p fg))
        (let ((shade (my/mix bg fg 0.12)))
          (set-face-attribute 'ml/name nil :background shade
                              :foreground (my/readable "#ffffff" shade)))
      (set-face-attribute 'ml/name nil :background 'unspecified))))

(ml/update-name-face)
(add-hook 'enable-theme-functions #'ml/update-name-face)

(defvar ml/message-height 0.75
  "Size of the messages in the bar, relative to the bar's text (the same
as treemacs's text, ui.el).")

(defvar ml/name-width 24
  "Columns of the buffer-name segment; the name is centered in it, and a
longer one is cut short with …")

(defun ml/segments (parts)
  "PARTS (strings) as segments, alternating colors, the first the lighter."
  (cl-loop for part in parts
           for i from 0
           concat (let ((text (concat " " part " ")))
                    ;; the segment's background under the part's own colors
                    (add-face-text-property 0 (length text)
                                            (if (cl-evenp i) 'ml/seg-b 'ml/seg-a)
                                            t text)
                    text)))

(defun ml/click-map (command)
  "A keymap running COMMAND when the text is clicked."
  (let ((map (make-sparse-keymap)))
    (keymap-set map "<mouse-1>" command)
    map))

(defun ml/main-window ()
  "The window you're working in: in the main frame, even from a popup."
  (frame-selected-window (if (and (pop/live-p) (eq (selected-frame) pop/frame))
                             (frame-parent pop/frame)
                           (selected-frame))))

(defun ml/diagnostics ()
  "E.g. \"✗ 2  ⚠ 3  \", colored, where flymake is checking (eglot turns
it on), or a check mark when there are none; nil elsewhere."
  (when (bound-and-true-p flymake-mode)
    (let ((errors 0) (warnings 0))
      (dolist (diag (flymake-diagnostics))
        (let ((severity (flymake--severity (flymake-diagnostic-type diag))))
          (cond ((>= severity (warning-numeric-level :error))   (cl-incf errors))
                ((>= severity (warning-numeric-level :warning)) (cl-incf warnings)))))
      (if (= 0 errors warnings)
          (propertize "✓  " 'face 'success)
        (concat (if (> errors 0) (propertize (format "✗ %d  " errors) 'face 'error) "")
                (if (> warnings 0) (propertize (format "⚠ %d  " warnings) 'face 'warning) ""))))))

(defun ml/name-segment ()
  "The current buffer's name, bold and centered in its segment, with a dot
if it has unsaved changes."
  (let* ((name (concat (if (derived-mode-p 'treemacs-mode)
                           "treemacs"     ; not its long internal name
                         (buffer-name))
                       (if (and buffer-file-name (buffer-modified-p))
                           (propertize " ●" 'face 'warning)
                         "")))
         (name (truncate-string-to-width name ml/name-width nil nil "…"))
         (pad (- ml/name-width (string-width name)))
         (text (concat (make-string (/ (1+ pad) 2) ?\s) name
                       (make-string (/ pad 2) ?\s))))
    (add-face-text-property 0 (length text) 'ml/name t text)
    text))

(defun ml/right-side ()
  "Diagnostics, line:column, then the slots, which are clickable."
  (concat
   (or (ml/diagnostics) "")
   (format-mode-line "%l:%C" nil (ml/main-window))
   " "
   (ml/segments
    (cl-loop for (label . cmd) in (ml/slots)
             for n from 1
             when label
             collect (propertize label
                                 'mouse-face 'mode-line-highlight
                                 'help-echo (format "F%d or mouse-1: %s" n cmd)
                                 'local-map (ml/click-map cmd))))))

(defun ml/line (message mini)
  "The bar for the bottom-line window MINI, as (LEFT . RIGHT): the name
and MESSAGE (its first line) cut short to fit, then the right side,
against the right edge."
  (with-current-buffer (window-buffer (ml/main-window))
    (let* ((px (lambda (s) (string-pixel-width s (window-buffer mini))))
           (left (concat (ml/name-segment) "  "))
           (right (ml/right-side))
           (column (funcall px " "))
           (msg-column (funcall px (propertize " " 'face
                                               `(:height ,ml/message-height))))
           (right-px (funcall px right))
           (room (- (window-body-width mini t) (funcall px left) right-px
                    (* 3 column)))
           (msg (truncate-string-to-width
                 (car (split-string (or message "") "\n"))
                 (max 0 (/ room (max 1 msg-column))) nil nil "…")))
      ;; the message in smaller text, over whatever faces it has
      (add-face-text-property 0 (length msg) `(:height ,ml/message-height)
                              t msg)
      ;; The right side ends at the right edge.  With no fringe, Emacs keeps
      ;; the last column for its "line cut off" mark, which `ml/draw' makes
      ;; a blank in the last segment's color, so the segment runs to the
      ;; edge.  (Spilling text into that column instead grows the line.)
      (cons (concat left msg)
            (concat (propertize " " 'display
                                `(space :align-to (- right-fringe (,right-px))))
                    right)))))

(defun ml/last-face (string)
  "The face STRING ends in (the last segment's)."
  (let ((face (get-text-property (1- (length string)) 'face string)))
    (if (consp face) (car (last face)) face)))

(defun ml/draw (&optional message)
  "Draw the bar, with MESSAGE (default: the current one), in the main
frame's bottom line only.  Replaces mini-echo's own drawing, which puts
the message first and drops everything else when both don't fit."
  (unless (active-minibuffer-window)
    (when-let* ((mini (minibuffer-window (window-frame (ml/main-window))))
                (line (ml/line (or message (current-message)) mini)))
      (set-window-hscroll mini 0)       ; never left scrolled sideways
      (set-window-fringes mini 0 0)     ; the bar runs edge to edge
      (set-window-margins mini 0 0)
      (let ((glyph (make-glyph-code ?\s (ml/last-face (cdr line)))))
        (dolist (buf ml/bar-buffers)
          (with-current-buffer buf
            ;; Set every time: the minibuffer's buffer loses its local
            ;; settings whenever a prompt ends
            (setq-local truncate-lines t  ; never wrap: see below
                        left-fringe-width 0 right-fringe-width 0 ; edge to edge
                        left-margin-width 0 right-margin-width 0)
            (unless buffer-display-table
              (setq-local buffer-display-table (make-display-table)))
            ;; the "line cut off" mark: a blank in the last segment's color
            (set-display-table-slot buffer-display-table 'truncation glyph))))
      (dolist (ov mini-echo-overlays)
        ;; the overlay shows the bar in place of the echo area's own text
        ;; (the right side goes after it: aligning to the right edge only
        ;; works there, not in a replacement)
        (overlay-put ov 'window mini)
        (overlay-put ov 'display (car line))
        (overlay-put ov 'after-string (cdr line))))))

;;;; The bar

(defvar ml/bar-buffers
  (mapcar #'get-buffer-create '(" *Echo Area 0*" " *Echo Area 1*" " *Minibuf-0*"))
  "The buffers the bottom line shows when there's no prompt.")

;; A prompt (and vertico's list under it) runs edge to edge too: each one
;; has a buffer of its own, which would otherwise bring back the frame's
;; fringes, a strip of background either side of every row
(defun ml/prompt-edge-to-edge ()
  "No fringes or margins around the prompt's window."
  (setq-local left-fringe-width 0 right-fringe-width 0
              left-margin-width 0 right-margin-width 0)
  (when-let* ((win (active-minibuffer-window)))
    (set-window-fringes win 0 0)
    (set-window-margins win 0 0)))

(add-hook 'minibuffer-setup-hook #'ml/prompt-edge-to-edge)

(use-package mini-echo
  :custom
  (mini-echo-window-divider-args '(t 2 2))    ; borders between windows (ui.el)
  :custom-face
  ;; the whole line in the bar's colors and size, like a mode line
  (mini-echo-minibuffer-window ((t :inherit mode-line)))
  :config
  ;; mini-echo hides the mode lines and keeps the bottom line updated (on a
  ;; timer, on messages, on resizes); the bar itself is drawn by ml/draw
  (advice-add 'mini-echo-update :override #'ml/draw)
  (advice-add 'mini-echo-update-overlays :override #'ml/draw)
  ;; (ml/draw never lets the bottom line wrap: a wrapped line grows taller,
  ;; which redraws the bar, which grows it again, freezing Emacs)
  (mini-echo-mode 1))

(provide 'modeline)
