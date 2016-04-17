#lang racket/base
(require (for-syntax racket/base racket/syntax))
(require racket/path)
(require "../setup.rkt" sugar/define sugar/file sugar/coerce sugar/test)


;; because it comes up all the time
(define+provide (dirname path)
  ;(coerce/path? . -> . path?)
  (define-values (dir name dir?) (split-path path))
  dir)


(define+provide (find-upward-from starting-path filename-to-find
                                  [exists-proc file-exists?])
  ;; use exists-proc to permit less strict matching.
  ;; for instance, maybe it's ok to find the source for the path.
  ;((coerce/path? coerce/path?)((path? . -> . any/c)) . ->* . (or/c #f path?))
  (parameterize ([current-directory (dirname (->complete-path starting-path))])
    (let loop ([dir (current-directory)][path filename-to-find])
      (and dir ; dir is #f when it hits the top of the filesystem
           (let ([completed-path (path->complete-path path)]) 
             (if (exists-proc completed-path)
                 (simplify-path completed-path)
                 (loop (dirname dir) (build-path 'up path))))))))


;; for files like svg that are not source in pollen terms,
;; but have a textual representation separate from their display.
(define+provide (sourceish? x)
  ;(any/c . -> . coerce/boolean?)
  (define sourceish-extensions (list "svg"))
  (with-handlers ([exn:fail? (λ(e) #f)])
    (and (member (get-ext x) sourceish-extensions) #t)))

(module-test-external
 (check-true (sourceish? "foo.svg"))
 (check-false (sourceish? "foo.gif")))


;; compare directories by their exploded path elements,
;; not by equal?, which will give wrong result if no slash on the end
(define+provide (directories-equal? dirx diry)
  ;(coerce/path? coerce/path? . -> . coerce/boolean?)
  (equal? (explode-path dirx) (explode-path diry)))

(module-test-external
 (check-true (directories-equal? "/Users/MB/foo" "/Users/MB/foo/"))
 (check-false (directories-equal? "/Users/MB/foo" "Users/MB/foo")))


(define (paths? x) (and (list? x) (andmap path? x)))
(define (complete-paths? x) (and (list? x) (andmap complete-path? x)))

(define+provide (path-visible? path)
  ;; make paths absolute to test whether files exist,
  ;; then convert back to relative
  (not (regexp-match #rx"^\\." (path->string path))))

(define+provide (visible-files dir)
  (let ([dir (->path dir)])
    (filter path-visible? 
            (map (λ(p) (find-relative-path dir p)) 
                 (filter file-exists? 
                         (directory-list dir #:build? #t))))))


(define+provide (escape-last-ext x [escape-char (setup:extension-escape-char)])
  ;((pathish?) (char?) . ->* . coerce/path?)
  ;; if x has a file extension, reattach it with the escape char
  (define current-ext (get-ext x))
  (->path
   (if current-ext
       (format "~a~a~a" (->string (remove-ext x)) escape-char current-ext)
       x)))

(module-test-external
 (require sugar/coerce)
 (check-equal? (escape-last-ext "foo") (->path "foo"))
 (check-equal? (escape-last-ext "foo.html") (->path "foo_html"))
 (check-equal? (escape-last-ext "foo.html" #\$) (->path "foo$html")))

(define second cadr)
(define third caddr)
(define (last x) (car (reverse x)))
(define+provide (unescape-ext x [escape-char (setup:extension-escape-char)])
  ;((coerce/string?) (char?) . ->* . coerce/path?)
  ;; if x has an escaped extension, unescape it.
  (define-values (base name dir?) (split-path x))
  (->path
   (cond
     [dir? x]
     [else
      (define x-parts (explode-path x))
      (define filename (last x-parts))
      (define escaped-extension-pat (pregexp (format "(.*)[~a](\\S+)$" escape-char)))
      (define results (regexp-match escaped-extension-pat (->string filename)))
      (if results
          (let* ([filename-without-ext (second results)]
                 [ext (third results)]
                 [new-filename (add-ext filename-without-ext ext)])
            (if (eq? base 'relative)
                new-filename
                (build-path base new-filename)))
          x)])))


(module-test-external
 (require sugar/coerce)
 (check-equal? (unescape-ext "foo") (->path "foo"))
 (check-equal? (unescape-ext "foo_") (->path "foo_"))
 (check-equal? (unescape-ext "foo_#$%") (->path "foo.#$%"))
 (check-equal? (unescape-ext "foo.html") (->path "foo.html"))
 (check-equal? (unescape-ext "foo_html") (->path "foo.html"))
 (check-equal? (unescape-ext "foo_dir/bar") (->path "foo_dir/bar"))
 (check-equal? (unescape-ext "foo_dir/bar.html") (->path "foo_dir/bar.html"))
 (check-equal? (unescape-ext "foo_dir/bar_html") (->path "foo_dir/bar.html"))
 (check-equal? (unescape-ext "foo$html" #\$) (->path "foo.html"))
 (check-equal? (unescape-ext "foo_bar__html") (->path "foo_bar_.html"))
 (check-equal? (unescape-ext "foo$bar$$html" #\$) (->path "foo$bar$.html")))


(define+provide (ext-in-poly-targets? ext [x #f])
  (member (->symbol ext) (apply setup:poly-targets (if x (list x) null))))

(module-test-external
 (check-equal? (ext-in-poly-targets? 'html) '(html))
 (check-equal? (ext-in-poly-targets? 'missing) #f))


(define+provide (has-poly-ext? x)
  (equal? (get-ext x) (->string (setup:poly-source-ext))))

(module-test-external
 (check-true (has-poly-ext? "foo.poly"))
 (check-false (has-poly-ext? "foo.wrong")))


(define+provide (has-inner-poly-ext? x)
  (and (get-ext x) (has-poly-ext? (unescape-ext (remove-ext x)))))

(module-test-external
 (check-true (has-inner-poly-ext? "foo.poly.pm"))
 (check-true (has-inner-poly-ext? "foo_poly.pp"))
 (check-false (has-inner-poly-ext? "foo.poly"))
 (check-false (has-inner-poly-ext? "foo.wrong.pm")))

(define-syntax (make-source-utility-functions stx)
  (syntax-case stx ()
    [(_ stem)
     (with-syntax ([setup:stem-source-ext (format-id stx "setup:~a-source-ext" #'stem)]
                   [stem-source? (format-id stx "~a-source?" #'stem)]
                   [get-stem-source (format-id stx "get-~a-source" #'stem)]
                   [has/is-stem-source? (format-id stx "has/is-~a-source?" #'stem)]
                   [->stem-source-path (format-id stx "->~a-source-path" #'stem)]
                   [->stem-source-paths (format-id stx "->~a-source-paths" #'stem)]
                   [->stem-source+output-paths (format-id stx "->~a-source+output-paths" #'stem)])
       #`(begin
           ;; does file have particular extension
           (define+provide/contract (stem-source? x)
             (any/c . -> . boolean?)
             (and (pathish? x) (has-ext? (->path x) (setup:stem-source-ext)) #t))
           
           ;; non-theoretical: want the first possible source that exists in the filesystem
           (define+provide/contract (get-stem-source x)
             (coerce/path? . -> . (or/c #f path?))
             (let ([source-paths (->stem-source-paths x)])
               (and source-paths (for/first ([sp (in-list source-paths)]
                                             #:when (file-exists? sp))
                                            sp))))
           
           ;; it's a file-ext source file, or a file that's the result of a file-ext source
           (define+provide (has/is-stem-source? x)
             (->boolean (and (pathish? x) (ormap (λ(proc) (proc (->path x))) (list stem-source? get-stem-source)))))
           
           ;; get first possible source path (does not check filesystem)
           (define+provide/contract (->stem-source-path x)
             (pathish? . -> . (or/c #f path?))
             (define paths (->stem-source-paths x))
             (and paths (car paths)))
           
           ;; get all possible source paths (does not check filesystem)
           (define (->stem-source-paths x)
             (define results (if (stem-source? x) 
                                 (list x) ; already has the source extension
                                 #,(if (eq? (syntax->datum #'stem) 'scribble)
                                       #'(if (x . has-ext? . 'html) ; different logic for scribble sources
                                             (list (add-ext (remove-ext* x) (setup:stem-source-ext)))
                                             #f)
                                       #'(let ([x-ext (get-ext x)]
                                               [source-ext (setup:stem-source-ext)])
                                           (append
                                            (list (add-ext x source-ext)) ; standard
                                            (if x-ext ; has existing ext, therefore needs escaped version
                                                (append
                                                 (list (add-ext (escape-last-ext x) source-ext))
                                                 (if (ext-in-poly-targets? x-ext x) ; needs multi + escaped multi
                                                     (let ([x-multi (add-ext (remove-ext x) (setup:poly-source-ext))])
                                                       (list
                                                        (add-ext x-multi (setup:stem-source-ext))
                                                        (add-ext (escape-last-ext x-multi) source-ext)))
                                                     null))
                                                null))))))
             (and results (map ->path results)))
           
           ;; coerce either a source or output file to both
           (define+provide (->stem-source+output-paths path)
             ;(pathish? . -> . (values path? path?))
             ;; get the real source path if available, otherwise a theoretical path
             (values (->complete-path (or (get-stem-source path) (->stem-source-path path)))
                     (->complete-path (->output-path path))))))]))

(make-source-utility-functions preproc)

(define+provide (->source+output-paths source-or-output-path)
  ;(complete-path? . -> . (values complete-path? complete-path?))
  ;; file-proc returns two values, but ormap only wants one
  (define file-proc (ormap (λ(test file-proc) (and (test source-or-output-path) file-proc))
                           (list has/is-null-source? has/is-preproc-source? has/is-markup-source? has/is-scribble-source? has/is-markdown-source? )
                           (list ->null-source+output-paths ->preproc-source+output-paths ->markup-source+output-paths ->scribble-source+output-paths ->markdown-source+output-paths )))
  (file-proc source-or-output-path))



(module-test-internal
 (require sugar/coerce) 
 (check-equal? (->preproc-source-paths (->path "foo.pp")) (list (->path "foo.pp")))
 (check-equal? (->preproc-source-paths (->path "foo.html")) (list (->path "foo.html.pp") (->path "foo_html.pp")
                                                                  (->path "foo.poly.pp") (->path "foo_poly.pp")))
 (check-equal? (->preproc-source-paths "foo") (list (->path "foo.pp")))
 (check-equal? (->preproc-source-paths 'foo) (list (->path "foo.pp"))))

(make-source-utility-functions null)

(make-source-utility-functions pagetree)

(make-source-utility-functions markup)

(module-test-internal
 (require sugar/coerce)
 (check-equal? (->markup-source-paths (->path "foo.pm")) (list (->path "foo.pm")))
 (check-equal? (->markup-source-paths (->path "foo.html")) (list (->path "foo.html.pm") (->path "foo_html.pm")
                                                                 (->path "foo.poly.pm") (->path "foo_poly.pm")))
 (check-equal? (->markup-source-paths "foo") (list (->path "foo.pm")))
 (check-equal? (->markup-source-paths 'foo) (list (->path "foo.pm"))))

(make-source-utility-functions markdown)

(module-test-internal
 (require sugar/coerce)
 (check-equal? (->markdown-source-paths (->path "foo.pmd")) (list (->path "foo.pmd")))
 (check-equal? (->markdown-source-paths (->path "foo.html")) (list (->path "foo.html.pmd") (->path "foo_html.pmd")
                                                                   (->path "foo.poly.pmd") (->path "foo_poly.pmd")))
 (check-equal? (->markdown-source-paths "foo") (list (->path "foo.pmd")))
 (check-equal? (->markdown-source-paths 'foo) (list (->path "foo.pmd"))))


(make-source-utility-functions scribble)


(define+provide/contract (get-source path)
  (coerce/path? . -> . (or/c #f path?))
  (ormap (λ(proc) (proc path)) (list get-markup-source get-markdown-source get-preproc-source get-null-source get-scribble-source)))

;; for backward compatibility
(define+provide ->source-path get-source)

(define+provide/contract (->output-path x)
  (coerce/path? . -> . coerce/path?)
  (cond
    [(or (markup-source? x) (preproc-source? x) (null-source? x) (markdown-source? x))
     (define output-path (unescape-ext (remove-ext x)))
     (if (has-poly-ext? output-path)
         (add-ext (remove-ext output-path) (or (current-poly-target) (car (setup:poly-targets))))
         output-path)]
    [(scribble-source? x) (add-ext (remove-ext x) 'html)]
    [else x]))


(define+provide (project-files-with-ext ext)
  ;(coerce/symbol? . -> . complete-paths?)
  (map ->complete-path (filter (λ(i) (has-ext? i (->symbol ext))) (directory-list (current-project-root)))))


(define (racket-source? x)
  (->boolean (and (pathish? x) (has-ext? (->path x) 'rkt))))


;; to identify unsaved sources in DrRacket
(define (unsaved-source? path-string)
  ((substring (->string path-string) 0 7) . equal? . "unsaved"))


(define (ends-with? str ender)
  (define pat (regexp (format "~a$" ender)))
  (and (regexp-match pat str) #t))
  

(define+provide (magic-directory? path)
  (and (directory-exists? path) 
       (or (ends-with? (path->string path) "compiled"))))


(define+provide (cache-file? path)
  (ormap (λ(cache-name) (ends-with? (path->string path) cache-name)) default-cache-names))


(define+provide (unpublished-path? file)
  (ormap (λ(proc) (proc file)) (list
                                preproc-source? 
                                markup-source?
                                markdown-source?
                                pagetree-source?
                                scribble-source?
                                null-source?
                                racket-source?
                                magic-directory?
                                cache-file?
                                (setup:unpublished-path?))))