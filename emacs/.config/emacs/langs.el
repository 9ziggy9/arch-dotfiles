;;; langs.el --- programming: indentation, C, eglot, compiling -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))
(require 'cl-lib)

;; Mode-specific popups go here, each with its mode's slots, which
;; replace the defaults (see `ml/mode-slots' in modeline.el):
;;
;;   (with-eval-after-load 'modeline
;;     (add-to-list 'ml/mode-slots
;;                  '(c-ts-mode ("compile" . pop/compile-toggle) ...)))

;;; Indentation: 2 columns, spaces, in every language

(defvar my/indent-width 2
  "Columns per indentation step, in every language.")

;; Each language has its own setting for its basic step.  These are set
;; before the modes load, so their defaults don't apply.  Only the basic
;; step: settings that are multiples or extras of it (Fortran continuation
;; lines, extra offsets for brackets in JS...) keep their defaults.
(defvar my/indent-variables
  '(standard-indent tab-width evil-shift-width ; < and >, evil's
    c-basic-offset c-ts-mode-indent-offset   ; C, C++, Java (cc-mode)
    python-indent-offset
    js-indent-level typescript-ts-mode-indent-offset json-ts-mode-indent-offset
    css-indent-offset sgml-basic-offset html-ts-mode-indent-offset
    nxml-child-indent
    sh-basic-offset smie-indent-basic       ; shells, and SMIE modes
    rust-ts-mode-indent-offset go-ts-mode-indent-offset
    java-ts-mode-indent-offset csharp-ts-mode-indent-offset
    lua-ts-mode-indent-offset php-ts-mode-indent-offset
    cmake-ts-mode-indent-offset toml-ts-mode-indent-offset
    elixir-ts-mode-indent-offset heex-ts-mode-indent-offset
    ruby-indent-level perl-indent-level cperl-indent-level
    tex-indent-basic
    pascal-indent-level verilog-indent-level vhdl-basic-offset)
  "Every language's setting for its basic indentation step.")

(setq-default indent-tabs-mode nil)
(dolist (var my/indent-variables)
  (set-default var my/indent-width))

;; Python measures the indentation of each file it opens and uses that
;; instead; no guessing
(setq python-indent-guess-indent-offset nil)

;; For any other language, and modes that set a width of their own when
;; they start (Python sets tab-width to 8, for instance): once a mode is
;; on, its own "<lang>-indent-offset" and the like are made 2 as well
(defun my/indent-width-here ()
  "Make this buffer's indentation step `my/indent-width', whatever its mode."
  (let* ((mode (symbol-name major-mode))
         (langs (delete-dups
                 (list (string-remove-suffix "-mode" mode)
                       (string-remove-suffix "-ts-mode" mode)))))
    (dolist (var (append
                  ;; c-basic-offset: cc-mode's styles (java's...) set their own
                  '(tab-width evil-shift-width standard-indent c-basic-offset)
                  (cl-loop for lang in langs
                           append (cl-loop for suffix in '("-indent-offset" "-mode-indent-offset"
                                                           "-basic-offset" "-indent-level")
                                           for var = (intern-soft (concat lang suffix))
                                           when var collect var))))
      (when (and (boundp var) (integerp (symbol-value var)))
        (set (make-local-variable var) my/indent-width)))))

(add-hook 'after-change-major-mode-hook #'my/indent-width-here)

;; Fill column: in code, the part of a line past it is drawn in red
(setq-default fill-column 80)

(use-package whitespace
  :ensure nil
  :hook (prog-mode . whitespace-mode)
  :custom
  (whitespace-style '(face lines-tail))
  (whitespace-line-column nil)          ; nil means use `fill-column'
  :custom-face
  (whitespace-line ((t (:background unspecified :weight unspecified))))
  :config
  ;; its red reads on the scheme's background (ui.el)
  (when (fboundp 'my/scheme-faces) (my/scheme-faces)))

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
  (c-ts-mode . my/c-macro-highlighting)
  (c-ts-mode . my/c-highlight-calls))

;; Function calls are highlighted too (italic, like definitions: ui.el).
;; Tree-sitter only does that at its top level of detail, which also
;; colors every variable, operator and bracket; this adds just the calls.
(defun my/c-highlight-calls ()
  "Highlight function calls, on top of the usual level of detail."
  (treesit-font-lock-recompute-features '(function)))

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

;; clangd's docs, signatures, highlighting of the symbol under the cursor
;; and code-action hints all come through eldoc.  Its docs go to the
;; *eldoc* buffer (M-x eldoc-doc-buffer), not the echo area, which is the
;; bar (modeline.el).
(defun my/eglot-docs-in-buffer ()
  "Show eldoc's docs in its buffer only, in buffers eglot manages."
  (if (eglot-managed-p)
      (setq-local eldoc-display-functions '(eldoc-display-in-buffer))
    (kill-local-variable 'eldoc-display-functions)))

(use-package eglot
  :ensure nil
  :hook
  (c-ts-mode . eglot-ensure)           ; start clangd in every C buffer
  (eglot-managed-mode . my/eglot-docs-in-buffer)
  :init
  ;; No error checking (flymake).  A plain variable, not an option, so set
  ;; here: :custom would be too early for it, before eglot is loaded
  (setq eglot-stay-out-of '(flymake))
  :custom
  (eglot-ignored-server-capabilities '(:inlayHintProvider)) ; no inline hints
  (eglot-autoshutdown t)               ; stop it when the last C buffer closes
  (eglot-extend-to-xref t)             ; headers you jump into reuse that clangd
  ;; No hints that clangd has a fix or refactoring for the code at point
  ;; (M-x eglot-code-actions still lists them)
  (eglot-code-action-indications nil)
  :config
  ;; clangd marks inactive #ifdef branches (e.g. an stb-style
  ;; #ifdef FOO_IMPLEMENTATION block) as "comment" tokens, greying them out;
  ;; tree-sitter already highlights real comments
  (setq eglot-semantic-token-types
        (delete "comment" eglot-semantic-token-types))
  ;; clangd tags symbols as declared, defined, modified, static... and
  ;; eglot paints most of those tags with the function or keyword faces,
  ;; over the symbol's own: every declared variable came out like a
  ;; function (italic) and static ones like keywords (bold), and macro
  ;; definitions kept the function look.  Keep the tags that say something
  ;; of their own.
  (setq eglot-semantic-token-modifiers
        '("readonly" "deprecated" "documentation" "defaultLibrary")))

;;; Documentation at point

;; ? in normal state, in code, shows the documentation of the function
;; (or whatever) under the cursor in a popup; escape (or q) closes it.  In
;; Emacs Lisp that's helpful's page for it; elsewhere it's what eldoc has,
;; e.g. clangd's docs in C, which can take a moment to arrive.  Outside
;; code, ? is still evil's search backward.  Help opened any other way
;; (C-h f...) shows in the popup too.

(defvar my/doc-requested nil
  "Non-nil while docs asked for with ? are on their way, to take focus.")

(defun my/doc-at-point ()
  "Show the documentation for the thing at point in a popup."
  (interactive)
  (if (derived-mode-p 'emacs-lisp-mode 'lisp-interaction-mode)
      (helpful-at-point)
    (setq my/doc-requested t)
    ;; asks every doc source and shows the *eldoc* buffer once they answer
    (eldoc t)))

(defun my/doc-take-focus ()
  "Focus the popup that docs just entered, once it's showing."
  (run-at-time 0 nil (lambda () (when (pop/visible-p) (pop/focus)))))

(pop/define doc
  :match   (string-match-p "\\`\\*eldoc" (buffer-name))
  :capture t
  :setup   (progn (pop/text-scale 0.8)
                  ;; eldoc rewrites this buffer as you move around; only
                  ;; take focus when the docs were asked for
                  (when my/doc-requested
                    (setq my/doc-requested nil)
                    (my/doc-take-focus)))
  :keys    ("q" pop/hide))

;; helpful just shows its pages (the popup takes focus itself, below);
;; letting it select the popup's window as well left the popup's keys off
(setq helpful-switch-buffer-function #'display-buffer)

(pop/define help
  :match   (derived-mode-p 'helpful-mode)
  :capture t
  :setup   (progn (pop/text-scale 0.8)
                  (my/doc-take-focus))
  :keys    ("q" pop/hide)
  :hints   ("RET" "follow link"  "q" "close"  "?" "keys"))

(with-eval-after-load 'evil
  (evil-define-key 'normal 'global
    "?" `(menu-item "" my/doc-at-point
                    :filter ,(lambda (cmd) (when (derived-mode-p 'prog-mode) cmd)))))

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
