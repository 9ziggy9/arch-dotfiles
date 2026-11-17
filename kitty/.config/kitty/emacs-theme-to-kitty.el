;;; emacs-theme-to-kitty.el --- print an emacs theme as kitty colors -*- lexical-binding: t -*-
;;
;; Run in batch mode, without touching any running emacs:
;;   emacs --batch -Q -l emacs-theme-to-kitty.el --list
;;   emacs --batch -Q -l emacs-theme-to-kitty.el --colors
;;   emacs --batch -Q -l emacs-theme-to-kitty.el THEME
;;
;; The theme is loaded but not enabled, and its face specs are read the way a
;; true-color graphical frame would pick them.  Terminal colors come from the
;; theme's ansi-color-* faces (or term-color-*); themes without those get a
;; palette built from their font-lock colors.

(require 'cl-lib)
(require 'color)

(setq user-emacs-directory (expand-file-name "~/.config/emacs/")
      custom-theme-directory user-emacs-directory
      package-user-dir (expand-file-name "elpa" user-emacs-directory))
(package-initialize)

;; Same as consult-themes in ui.el: color themes only
(defvar e2k-excluded '(newcomers-presets light-blue base16))

;; Selections and the active tab use the amber that ui.el forces on region
;; and hl-line in every emacs theme
(defvar e2k-amber "#c9a66b")
(defvar e2k-amber-text "#1c1c1c")

(defvar e2k-settings nil "Face specs of the theme being converted.")
(defvar e2k-background-mode nil "dark or light, once known.")

(defun e2k-hex (c)
  "C as #rrggbb, or nil when it is not a usable color."
  (when (and (stringp c) (not (string-prefix-p "unspecified" c)))
    (let ((rgb (cond
                ((string-match "\\`#\\([[:xdigit:]]+\\)\\'" c)
                 (let* ((h (match-string 1 c))
                        (n (/ (length h) 3)))
                   (when (and (memq (length h) '(3 6 9 12)))
                     (mapcar (lambda (i)
                               (/ (float (string-to-number
                                          (substring h (* i n) (* (1+ i) n)) 16))
                                  (1- (expt 16 n))))
                             '(0 1 2)))))
                ((not (string-prefix-p "color-" c))
                 (let ((v (ignore-errors (tty-color-standard-values (downcase c)))))
                   (when v (mapcar (lambda (x) (/ x 65535.0)) v)))))))
      (when rgb (apply #'color-rgb-to-hex (append rgb '(2)))))))

(defun e2k-display-ok (display)
  "Whether DISPLAY matches a true-color graphical frame."
  (or (memq display '(t default))
      (cl-every
       (lambda (cond)
         (pcase cond
           (`(type . ,types) (cl-intersection types '(graphic x w32 ns pgtk)))
           (`(class . ,classes) (memq 'color classes))
           (`(min-colors ,_) t)
           (`(background . ,modes)
            (or (null e2k-background-mode) (memq e2k-background-mode modes)))
           (`(supports . ,_) t)
           (_ nil)))
       display)))

(defun e2k-attrs (face)
  "Attribute plist FACE gets in the theme, or nil."
  (let ((spec (nth 2 (assq face (mapcar #'cdr e2k-settings)))))
    (cl-loop for (display . rest) in spec
             when (e2k-display-ok display)
             return (if (keywordp (car rest)) rest (car rest)))))

(defun e2k-attr (face attr &optional depth)
  "FACE's ATTR as #rrggbb, following :inherit."
  (let* ((depth (or depth 0))
         (plist (e2k-attrs face))
         (own (e2k-hex (plist-get plist attr))))
    (or own
        (when (< depth 6)
          (let ((parents (plist-get plist :inherit)))
            (cl-some (lambda (p) (and (symbolp p) (e2k-attr p attr (1+ depth))))
                     (if (listp parents) parents (list parents))))))))

(defun e2k-fg (&rest faces)
  (cl-some (lambda (f) (e2k-attr f :foreground)) faces))

(defun e2k-rgb (hex)
  "#rrggbb HEX as a list of floats; color-name-to-rgb is unreliable in batch."
  (mapcar (lambda (i) (/ (string-to-number (substring hex i (+ i 2)) 16) 255.0))
          '(1 3 5)))

(defun e2k-mix (a b frac)
  "A with FRAC of B mixed in."
  (apply #'color-rgb-to-hex
         (append (cl-mapcar (lambda (x y) (+ x (* frac (- y x))))
                            (e2k-rgb a) (e2k-rgb b))
                 '(2))))

(defun e2k-dark-p (c)
  (< (apply #'+ (cl-mapcar #'* '(0.2126 0.7152 0.0722) (e2k-rgb c))) 0.5))

(defun e2k-theme-colors ()
  "Every saturated foreground color the theme sets, as (HEX HUE SAT LUM)."
  (let (out)
    (dolist (e e2k-settings)
      (when (eq (car e) 'theme-face)
        (let ((c (e2k-hex (plist-get (e2k-attrs (nth 1 e)) :foreground))))
          (when (and c (not (assoc c out)))
            (let ((hsl (apply #'color-rgb-to-hsl (e2k-rgb c))))
              (when (and (> (nth 1 hsl) 0.25) (< 0.25 (nth 2 hsl) 0.85))
                (push (cons c hsl) out)))))))
    out))

(defun e2k-hue-palette (bg fg)
  "black..white for BG and FG, the hues taken from the theme's colors."
  (let ((colors (e2k-theme-colors))
        (dark (e2k-dark-p bg)))
    (append
     (list (e2k-mix bg fg 0.15))
     (mapcar
      (lambda (target)
        (let* ((dist (lambda (h) (let ((d (abs (- (* 360 h) target))))
                                   (min d (- 360 d)))))
               (best (car (sort (cl-remove-if-not
                                 (lambda (c) (< (funcall dist (nth 1 c)) 35))
                                 (copy-sequence colors))
                                (lambda (a b) (< (funcall dist (nth 1 a))
                                                 (funcall dist (nth 1 b))))))))
          (or (car best)
              ;; the theme has no such hue: a soft one that suits it
              (apply #'color-rgb-to-hex
                     (append (color-hsl-to-rgb (/ target 360.0) 0.5
                                               (if dark 0.65 0.4))
                             '(2))))))
      '(0 120 55 220 300 180))            ; red green yellow blue magenta cyan
     (list (e2k-mix bg fg 0.8)))))

(defun e2k-list ()
  (dolist (th (sort (cl-set-difference (custom-available-themes) e2k-excluded)
                    (lambda (a b) (string< a b))))
    (princ (format "%s\n" th))))

(defun e2k-colors ()
  "Print THEME BACKGROUND FOREGROUND for every theme --list gives."
  (dolist (th (sort (cl-set-difference (custom-available-themes) e2k-excluded)
                    (lambda (a b) (string< a b))))
    (ignore-errors
      (load-theme th t t)
      (setq e2k-settings (get th 'theme-settings)
            e2k-background-mode nil)
      (princ (format "%s %s %s\n" th
                     (or (e2k-attr 'default :background) "#000000")
                     (or (e2k-attr 'default :foreground) "#ffffff"))))))

(defun e2k-convert (theme)
  (load-theme theme t t)
  (setq e2k-settings (get theme 'theme-settings))
  (let* ((bg (or (e2k-attr 'default :background) "#000000"))
         (fg (or (e2k-attr 'default :foreground) "#ffffff"))
         (_ (setq e2k-background-mode (if (e2k-dark-p bg) 'dark 'light)))
         (names '("black" "red" "green" "yellow" "blue" "magenta" "cyan" "white"))
         ;; for themes without terminal faces: the theme's own color nearest
         ;; each ANSI hue
         (fallback (e2k-hue-palette bg fg))
         (toward (if (eq e2k-background-mode 'dark) "#ffffff" "#000000"))
         (normal (cl-mapcar
                  (lambda (n fb)
                    (or (e2k-fg (intern (concat "ansi-color-" n))
                                (intern (concat "term-color-" n)))
                        (e2k-attr (intern (concat "term-color-" n)) :background)
                        fb))
                  names fallback))
         (bright (cl-mapcar
                  (lambda (n c i)
                    (or (e2k-fg (intern (concat "ansi-color-bright-" n)))
                        (pcase i
                          (0 (e2k-mix bg fg 0.45))
                          (7 fg)
                          (_ (e2k-mix c toward 0.15)))))
                  names normal (number-sequence 0 7)))
         (cursor (or (e2k-attr 'cursor :background) fg))
         (divider (e2k-mix bg fg 0.25)))
    (princ (format "# kitty colors from emacs theme `%s' (generated)\n\n" theme))
    (dolist (kv `(("background" ,bg) ("foreground" ,fg)
                  ("cursor" ,cursor) ("cursor_text_color" ,bg)
                  ("selection_background" ,e2k-amber)
                  ("selection_foreground" ,e2k-amber-text)
                  ("url_color" ,(nth 4 normal))
                  ("active_border_color" ,e2k-amber)
                  ("inactive_border_color" ,divider)
                  ("tab_bar_background" ,bg)
                  ("active_tab_background" ,e2k-amber)
                  ("active_tab_foreground" ,e2k-amber-text)
                  ("inactive_tab_background" ,(e2k-mix bg fg 0.12))
                  ("inactive_tab_foreground" ,(e2k-mix bg fg 0.6))))
      (princ (format "%-24s %s\n" (car kv) (cadr kv))))
    (princ "\n")
    (cl-loop for c in (append normal bright) for i from 0
             do (princ (format "color%-3d %s\n" i c)))))

(let ((arg (car command-line-args-left)))
  (setq command-line-args-left nil)
  (cond ((equal arg "--list") (e2k-list))
        ((equal arg "--colors") (e2k-colors))
        (arg (e2k-convert (intern arg)))
        (t (message "usage: emacs --batch -Q -l %s --list | --colors | THEME" load-file-name)
           (kill-emacs 1))))

;;; emacs-theme-to-kitty.el ends here
