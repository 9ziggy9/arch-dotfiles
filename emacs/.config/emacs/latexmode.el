;;; latexmode.el --- LaTeX, snippets, live PDF preview -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))

;;; LaTeX

;; .tex files, as plain text with colours: nothing is drawn as symbols,
;; raised or shrunk; \partial, x^2 and \frac{a}{b} stay exactly as typed
(use-package tex-mode
  :ensure nil
  :defer t
  :custom
  (tex-default-mode 'latex-mode)        ; a new, empty .tex is LaTeX too
  (tex-fontify-script nil))             ; x^2, x_i: no raised or smaller text

;;; Snippets

;; Type a snippet's name, e.g. <dm, and pick it from the completion
;; popup; Tab and S-Tab then move between its blanks.  The names all
;; start with <, so words like al, sum or item never bring them up.
;; The snippets are in templates.eld; the math ones work in org too.
(use-package tempel
  :custom
  (tempel-path (locate-user-emacs-file "templates.eld"))
  :hook
  ((latex-mode org-mode) . my/tempel-setup)
  :bind (:map tempel-map
         ("<tab>"     . tempel-next)
         ("TAB"       . tempel-next)
         ("<backtab>" . tempel-previous)))

(defun my/tempel-complete ()
  "Snippets for the word before point, if it starts with <."
  (when (looking-back "<[[:alpha:]]*" (line-beginning-position))
    (tempel-complete)))

(defun my/tempel-setup ()
  "Offer snippets in the completion popup, ahead of other completions."
  (add-hook 'completion-at-point-functions #'my/tempel-complete -90 t)
  ;; A complete name (<dm) matches just itself; show it anyway, so RET
  ;; can expand it, rather than the popup staying away
  (setq-local corfu-on-exact-match 'show))

;;; Live PDF preview

;; The pdf slot shows the document as a PDF in a split on its right; the
;; slot again stops it.  latexmk runs in the background in watch mode
;; (-pvc), rebuilding whenever the .tex changes, and the PDF view reloads
;; itself (global-auto-revert-mode, init.el).  A .tex file is built as it
;; is; an org file is exported to a .tex next to it on every save, as with
;; export.  The PDF and LaTeX's other files go to a temporary directory.

(use-package pdf-tools                  ; PDFs open in pdf-view-mode
  :defer t
  :init (pdf-loader-install)            ; builds its helper the first time
  :custom (pdf-view-display-size 'fit-width)
  :config
  ;; Its page-prefetch timer can fire while a PDF is still opening, before
  ;; the window has a page, and errors; it repeats, so just wait for one
  (advice-add 'pdf-cache--prefetch-start :before-while
              (lambda (&rest _) (pdf-view-current-page))))

(defvar-local my/pdf-process nil "The running latexmk, if any.")

(defun my/pdf-file ()
  "Where the current document's preview PDF goes."
  (expand-file-name (concat (file-name-base buffer-file-name) ".pdf")
                    (file-name-concat temporary-file-directory "pdf-preview"
                                      (md5 buffer-file-name))))

(defun my/pdf-export ()
  "Export this org file to the .tex latexmk is watching; return its name."
  (expand-file-name (org-latex-export-to-latex)))

(defun my/pdf-output (buf pdf)
  "A process filter: report latexmk's progress, and show PDF beside BUF
once it's first built."
  (lambda (_proc text)
    (cond ((string-match "^! .*" text)
           (message "LaTeX failed: %s" (match-string 0 text)))
          ((and (string-match-p "Output written on" text) (buffer-live-p buf))
           (message "PDF updated")
           ;; Not from inside the filter: opening a PDF waits on pdf-tools'
           ;; own process, which a filter can't
           (run-at-time 0 nil #'my/pdf-show buf pdf)))))

(defun my/pdf-show (buf pdf)
  "Show PDF in a split right of BUF's window, unless it's showing already."
  (let ((win (get-buffer-window buf)))
    (unless (or (find-buffer-visiting pdf) (not win))
      ;; Opened from inside its window, so pdf-tools sizes the pages for
      ;; that window from the start
      (with-selected-window (split-window win nil 'right)
        (find-file pdf)))))

(define-minor-mode my/pdf-mode
  "Keep a PDF of this document beside it, rebuilt as it changes."
  :lighter nil
  (if my/pdf-mode
      (let ((tex (if (derived-mode-p 'org-mode) (my/pdf-export) buffer-file-name))
            (pdf (my/pdf-file)))
        (unless (executable-find "latexmk")
          (setq my/pdf-mode nil)
          (user-error "No latexmk: install TeX Live (see README)"))
        (when (derived-mode-p 'org-mode)
          (add-hook 'after-save-hook #'my/pdf-export nil t))
        (add-hook 'kill-buffer-hook (lambda () (my/pdf-mode -1)) nil t)
        (make-directory (file-name-directory pdf) t)
        (setq my/pdf-process
              (make-process
               :name "pdf-build" :buffer " *pdf build*" :noquery t
               :command (list "latexmk" "-pdf" "-pvc" "-view=none"
                              "-interaction=nonstopmode" "-halt-on-error"
                              (concat "-outdir=" (file-name-directory pdf))
                              (file-name-nondirectory tex))
               :filter (my/pdf-output (current-buffer) pdf))))
    (remove-hook 'after-save-hook #'my/pdf-export t)
    (when (process-live-p my/pdf-process)
      (kill-process my/pdf-process))
    (when-let* ((view (and buffer-file-name (find-buffer-visiting (my/pdf-file)))))
      (dolist (win (get-buffer-window-list view nil t))
        (delete-window win))
      (kill-buffer view))))

(defun my/pdf-toggle ()
  "Start or stop the live PDF preview of the org or LaTeX file you're in."
  (interactive)
  (pop/leave)
  (unless (and (derived-mode-p 'org-mode 'latex-mode) buffer-file-name)
    (user-error "The PDF preview is for org and LaTeX files"))
  (my/pdf-mode 'toggle))

;; Org and LaTeX files get the pdf slot after the usual ones
(with-eval-after-load 'modeline
  (dolist (mode '(org-mode latex-mode))
    (add-to-list 'ml/mode-slots
                 `(,mode ,@ml/default-slots ("pdf" . my/pdf-toggle)))))

(provide 'latexmode)
