;; Snippets (tempel; see latexmode.el).  Type a name, e.g. <dm, pick
;; it from the popup, then Tab / S-Tab move between the blanks.
;;   p  a blank          q  where the cursor ends up
;;   n  a new line       >  indent the line
;;   (s name) a blank repeated wherever name appears again

latex-mode org-mode

;; Math
(<mk "$" q "$")                                         ; inline math
(<dm "\\[" n> q n "\\]" >)                              ; centered, unnumbered
(<eq "\\begin{equation}" n> q n "\\end{equation}" >)    ; centered, numbered
(<eqs "\\begin{equation*}" n> q n "\\end{equation*}" >)
(<al "\\begin{align}" n> q n "\\end{align}" >)          ; lined up at &, numbered
(<als "\\begin{align*}" n> q n "\\end{align*}" >)
(<cases "\\begin{cases}" n> p " & " p " \\\\" n> p " & " p n "\\end{cases}" >)
(<mat "\\begin{pmatrix}" n> q n "\\end{pmatrix}" >)
(<fr "\\frac{" p "}{" p "}" q)
(<pd "\\frac{\\partial " p "}{\\partial " p "}" q)
(<sum "\\sum_{" p "}^{" p "} " q)
(<int "\\int_{" p "}^{" p "} " p " \\, d" p q)
(<beg "\\begin{" (s env) "}" > n> r> n "\\end{" env "}" >) ; any environment

latex-mode

;; Documents
(<doc "\\documentclass{article}" n
     "\\usepackage{amsmath, amssymb}" n n
     "\\title{" p "}" n
     "\\author{" p "}" n n
     "\\begin{document}" n
     "\\maketitle" n n
     q n n
     "\\end{document}")
(<sec "\\section{" p "}" n q)
(<ssec "\\subsection{" p "}" n q)
(<item "\\begin{itemize}" n> "\\item " q n "\\end{itemize}" >)
(<enum "\\begin{enumerate}" n> "\\item " q n "\\end{enumerate}" >)
(<fig "\\begin{figure}[h]" n>
     "\\centering" n>
     "\\includegraphics[width=0.8\\linewidth]{" p "}" n>
     "\\caption{" p "}" n
     "\\end{figure}" >)
