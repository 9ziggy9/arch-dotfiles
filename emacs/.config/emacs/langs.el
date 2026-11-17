;;; langs.el --- programming: indentation, C, eglot, compiling -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))

;; Mode-specific popups go here, each with its mode's slots, which
;; replace the defaults (see `ml/mode-slots' in modeline.el):
;;
;;   (with-eval-after-load 'modeline
;;     (add-to-list 'ml/mode-slots
;;                  '(c-ts-mode ("compile" . pop/compile-toggle) ...)))

;; Indentation
(setq-default indent-tabs-mode nil
              tab-width 2
              c-basic-offset 2
              standard-indent 2)

;; Fill column: in code, the part of a line past it is drawn in red
(setq-default fill-column 80)

(use-package whitespace
  :ensure nil
  :hook (prog-mode . whitespace-mode)
  :custom
  (whitespace-style '(face lines-tail))
  (whitespace-line-column nil)          ; nil means use `fill-column'
  :custom-face
  (whitespace-line ((t (:foreground "#ff5f5f" :background unspecified
                        :weight unspecified)))))

;;; C
(use-package c-ts-mode
  :ensure nil
  :init
  ;; Use the tree-sitter modes for .c and .h files
  (add-to-list 'major-mode-remap-alist '(c-mode . c-ts-mode))
  (add-to-list 'major-mode-remap-alist '(c-or-c++-mode . c-or-c++-ts-mode))
  :config
  ;; Where to fetch the C grammar from
  (add-to-list 'treesit-language-source-alist
               '(c "https://github.com/tree-sitter/tree-sitter-c"))
  :custom
  (c-ts-mode-indent-offset 2)
  (c-ts-mode-indent-style 'k&r)
  :bind (:map c-ts-mode-map
         ("C-c '" . my/c-edit-macro)
         ("RET"   . my/c-macro-newline))
  :hook
  (c-ts-mode . electric-pair-local-mode)
  (c-ts-mode . my/c-macro-highlighting))

;;; Macros

;; A new line in a macro continues it: RET (or o / O) on a line ending
;; in a backslash gives the new line one too, lined up with the one above,
;; and indents it like the line above (one step more after a `{').  RET in
;; the middle of such a line gives both halves one.  RET on the macro's
;; last line (no backslash) is a plain RET, which ends the macro.  C-c '
;; (below) lines all the backslashes up again.

(defun my/c-backslash-column ()
  "Column of the backslash ending the current line, or nil."
  (save-excursion
    (end-of-line)
    (and (eq (char-before) ?\\)
         (1- (current-column)))))

(defun my/c-add-backslash (column)
  "End the current line with a backslash, at COLUMN if the text leaves room."
  (save-excursion
    (end-of-line)
    (unless (save-excursion (skip-chars-backward " \t") (bolp))
      (delete-horizontal-space))
    (indent-to (max column (1+ (current-column))))
    (insert "\\")))

(defun my/c-macro-indent (pos)
  "Indentation for a macro line after the text before POS on its line."
  (save-excursion
    (goto-char pos)
    (skip-chars-backward " \t\\\\")
    (+ (current-indentation)
       (if (eq (char-before) ?{) c-ts-indent-offset 0))))

(defun my/c-macro-newline ()
  "RET, but on a line ending in a backslash, continue the macro."
  (interactive)
  (let ((col (my/c-backslash-column))
        (text-end (save-excursion
                    (end-of-line)
                    (skip-chars-backward " \t\\\\")
                    (point))))
    (cond
     ((not col)
      (call-interactively #'newline))
     ;; At the start of the line: a new, empty macro line above it
     ((save-excursion (skip-chars-backward " \t") (bolp))
      (let ((indent (current-indentation)))
        (beginning-of-line)
        (insert (make-string indent ?\s) "\n")
        (forward-line -1)
        (my/c-add-backslash col)
        (forward-line 1)
        (back-to-indentation)))
     (t
      (goto-char (min (point) text-end))
      (let ((rest (string-trim (buffer-substring (point) text-end)))
            (indent (my/c-macro-indent (point))))
        (delete-region (point) (pos-eol))
        (my/c-add-backslash col)
        (end-of-line)
        (insert "\n" (make-string indent ?\s))
        (save-excursion
          (insert rest)
          (my/c-add-backslash col)))))))

(defun my/c-macro-after-open (&rest _)
  "After evil's o / O inside a macro, indent the new line and continue it."
  (when (derived-mode-p 'c-ts-mode)
    (let ((col (save-excursion
                 (and (zerop (forward-line -1)) (my/c-backslash-column)))))
      (when (and col (not (my/c-backslash-column)))
        (indent-line-to (my/c-macro-indent (save-excursion
                                             (forward-line -1)
                                             (pos-eol))))
        (my/c-add-backslash col)))))

(with-eval-after-load 'evil
  (advice-add 'evil-open-below :after #'my/c-macro-after-open)
  (advice-add 'evil-open-above :after #'my/c-macro-after-open))

;; tree-sitter reads a #define's body as one opaque chunk of text, so none
;; of it gets colored; parse each body again, as C of its own
(defun my/c-macro-highlighting ()
  "Highlight the code inside #define bodies."
  (setq-local treesit-range-settings
              (append treesit-range-settings
                      (treesit-range-rules
                       :embed 'c :host 'c :local t
                       '((preproc_arg) @body)))))

;; C-c ' on a #define opens it in a buffer of its own without the
;; backslashes, the body on the lines under the #define, so it indents
;; like any code.  C-c ' (or C-c C-c) puts it back with the backslashes
;; lined up; C-c C-k throws the edit away.  Not on a #define, it starts a
;; new one there.

(defvar-local my/c-macro-target nil
  "In a macro edit buffer: (BUFFER START END) of the text it replaces.")

(defvar-keymap my/c-macro-edit-mode-map
  "C-c '"   #'my/c-macro-commit
  "C-c C-c" #'my/c-macro-commit
  "C-c C-k" #'my/c-macro-abort)

(define-minor-mode my/c-macro-edit-mode
  "Editing a C macro without its backslashes."
  :keymap my/c-macro-edit-mode-map
  (setq-local header-line-format
              (substitute-command-keys
               " Macro: \\[my/c-macro-commit] to put it back, \\[my/c-macro-abort] to cancel")))

(defun my/c-macro-body-lines (text)
  "TEXT, a macro body, as lines without backslashes or shared indentation."
  (let* ((lines (split-string
                 (string-trim (replace-regexp-in-string "[ \t]*\\\\\n" "\n" text))
                 "\n"))
         (rest (cdr lines))
         (indent (apply #'min most-positive-fixnum
                        (mapcar (lambda (l) (string-match "[^ \t]" l))
                                (seq-remove #'string-blank-p rest)))))
    (cons (car lines)
          (mapcar (lambda (l) (if (string-blank-p l) "" (substring l indent)))
                  rest))))

(defun my/c-macro-end (start)
  "End of the #define at START, after its last backslash-continued line.
Worked out from the text: tree-sitter cuts a macro short at a comment
followed by a backslash."
  (save-excursion
    (goto-char start)
    (while (and (looking-at-p ".*\\\\$") (zerop (forward-line 1))))
    (min (point-max) (1+ (pos-eol)))))

(defun my/c-edit-macro ()
  "Edit the #define at point in its own buffer, without the backslashes."
  (interactive)
  (let* ((node (treesit-parent-until
                (treesit-node-at (point) treesit-primary-parser)
                (lambda (n) (member (treesit-node-type n)
                                    '("preproc_def" "preproc_function_def")))
                t))
         (start (if node (treesit-node-start node) (line-beginning-position)))
         (end (if node (my/c-macro-end start) start))
         (value (and node (treesit-node-child-by-field-name node "value")))
         (header (string-trim-right
                  (cond (value (buffer-substring-no-properties
                                start (treesit-node-start value)))
                        (node (buffer-substring-no-properties start end))
                        (t "#define "))
                  "[ \t\n\\\\]+"))
         (body (and value (my/c-macro-body-lines
                           (buffer-substring-no-properties
                            (treesit-node-start value) end))))
         (target (list (current-buffer) (copy-marker start) (copy-marker end)))
         (buf (generate-new-buffer "*macro*")))
    (with-current-buffer buf
      (insert header (if node "" " "))
      (when body
        (insert "\n" (string-join body "\n")))
      ;; No clangd here: the buffer isn't a file it could look at
      (let ((c-ts-mode-hook (remq 'eglot-ensure c-ts-mode-hook)))
        (c-ts-mode))
      (my/c-macro-edit-mode 1)
      (setq my/c-macro-target target)
      (goto-char (if body (pos-eol 2) (point-max))))
    (pop-to-buffer buf)))

(defun my/c-macro-commit ()
  "Put the edited macro back, with a backslash at the end of each line."
  (interactive)
  (pcase-let* ((`(,source ,start ,end) my/c-macro-target)
               (`(,header . ,body)
                (split-string (string-trim-right (buffer-string)) "\n"))
               (pad (make-string c-ts-indent-offset ?\s))
               (lines (if (cdr body)
                          (cons header
                                (mapcar (lambda (l)
                                          (if (string-blank-p l) "" (concat pad l)))
                                        body))
                        ;; A one-line body fits on the #define's line
                        (list (string-join (cons (string-trim-right header) body)
                                           " "))))
               (width (1+ (apply #'max (mapcar #'string-width lines))))
               (text (concat (mapconcat (lambda (l)
                                          (concat (string-pad l width) "\\"))
                                        (butlast lines) "\n")
                             (and (cdr lines) "\n")
                             (car (last lines)) "\n")))
    (unless (buffer-live-p source)
      (user-error "The file this macro came from is gone"))
    (quit-window t)
    (pop-to-buffer source)
    (goto-char start)
    (delete-region start end)
    (insert text)
    (goto-char start)))

(defun my/c-macro-abort ()
  "Throw the macro edit away."
  (interactive)
  (let ((source (car my/c-macro-target)))
    (quit-window t)
    (when (buffer-live-p source)
      (pop-to-buffer source))))

;;; Language server
(use-package consult-eglot              ; project-wide symbols, via clangd
  :after (consult eglot))

(use-package eldoc
  :ensure nil
  :custom
  (eldoc-idle-delay 0.2)                 ; pause before docs appear (default 0.5)
  (eldoc-echo-area-use-multiline-p nil)  ; one line, like other messages
  (eldoc-echo-area-prefer-doc-buffer t)) ; if *eldoc* is open, show docs there instead

(use-package eglot
  :ensure nil
  :hook (c-ts-mode . eglot-ensure)     ; start clangd in every C buffer
  :init
  (setq eglot-stay-out-of '(eldoc))    ; keep eglot out of the echo area
  :custom
  (eglot-ignored-server-capabilities '(:inlayHintProvider)) ; no inline hints
  (eglot-autoshutdown t)               ; stop it when the last C buffer closes
  (eglot-extend-to-xref t)             ; headers you jump into reuse that clangd
  :config
  ;; clangd marks inactive #ifdef branches (e.g. an stb-style
  ;; #ifdef FOO_IMPLEMENTATION block) as "comment" tokens, greying them out;
  ;; tree-sitter already highlights real comments
  (setq eglot-semantic-token-types
        (delete "comment" eglot-semantic-token-types)))

;;; Compilation

(setq compilation-always-kill t               ; new compile kills old, no prompt
      compilation-scroll-output 'first-error) ; follow output, stop at 1st error

;; Render gcc's colored output instead of showing raw escape codes
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)

;; Compiles run from the project root of the file you're in (or its own
;; directory, outside a project), like `project-compile'

(defun pop/compile-buffer ()
  "The compilation buffer, pointed at the current project's root."
  (let ((dir (with-current-buffer (pop/main-buffer)
               (if-let* ((project (project-current)))
                   (expand-file-name (project-root project))
                 default-directory))))
    (with-current-buffer (get-buffer-create "*compilation*")
      (unless (derived-mode-p 'compilation-mode)
        (compilation-mode))
      ;; Leave a running compile alone; changing directory mid-run would
      ;; break finding the files its errors point at
      (unless (get-buffer-process (current-buffer))
        (setq default-directory dir
              compilation-directory dir))
      (current-buffer))))

(defun pop/compile-prompt ()
  "Prompt for a compile command in the popup's minibuffer and run it.
The prompt starts with the last command, so C-<return> twice reruns it."
  (interactive)
  (compile (read-shell-command "Compile: " compile-command 'compile-history))
  (pop/focus))

(defun pop/compile-goto-error ()
  "Hide the popup and jump to the error at point in the main frame."
  (interactive)
  (let ((buf (current-buffer))
        (pos (point))
        ;; Jumping makes compile re-display its buffer; keep the popup hidden
        (pop/suppress t))
    (pop/hide)
    (with-current-buffer buf
      (goto-char pos)
      (compile-goto-error))
    (pop/hide)))

(defun pop/compile-rerun ()
  "Run the last compile command again."
  (interactive)
  (recompile)
  (pop/focus))

(pop/define compile
  :match   (derived-mode-p 'compilation-mode)
  :open    #'pop/compile-buffer
  :capture t
  :setup   (pop/text-scale 0.8)
  :keys    ("RET"        pop/compile-goto-error
            "C-<return>" pop/compile-prompt
            "r"          pop/compile-rerun
            "n"          compilation-next-error
            "p"          compilation-previous-error
            "K"          kill-compilation
            "q"          pop/hide)
  :hints   ("C-RET" "compile"  "r" "rerun"  "n/p" "next/prev error"
            "K" "stop"  "?" "keys"))

(provide 'langs)
