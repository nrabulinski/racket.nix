#lang racket/base

(require racket/cmdline
         racket/port
         racket/function
         racket/match
         racket/string
         racket/hash
         racket/pretty)

(define ((make-path root) path) (format "~a/~a" root path))

(define (make-config prev layer-path user-layer extra-lib-dirs)
  (define out (make-path layer-path))
  ; Gets a value from the previous config. Errors if it wasn't present
  (define (get-prev sym) (hash-ref prev sym))
  ; Gets a value from the previous config and puts it in a list.
  ; If it wasn't present the returned list will be empty.
  (define (get-prev-opt sym)
    (define prev-val (hash-ref prev sym #f))
    (if prev-val (list prev-val) '()))
  ; Gets a value from the previous config which was a list and removes any falsy values from it.
  (define (get-prev-list sym)
    (define prev-val (hash-ref prev sym #f))
    (if prev-val (filter identity prev-val) '()))
  (define prev-share-dir (get-prev 'share-dir))
  (define prev-links-file
    (or (hash-ref prev 'links-file #f)
        ((make-path prev-share-dir) "links.rktd")))
  (define prev-compiled-file-roots
    (filter (lambda (val) (not (equal? 'same val)))
            (get-prev-list 'compiled-file-roots)))
  ; New layer's values
  (define new-layer-config (hash
    'doc-dir (out "share/doc/racket")
    'lib-dir (out "lib/racket")
    'pkgs-dir (out "share/racket/pkgs")
    'share-dir (out "share/racket")
    'include-dir (out "include/racket")
    'apps-dir (out "share/applications")
    'man-dir (out "share/man")
    'bin-dir (out "bogus-bin")
    'gui-bin-dir (out "bogus-bin")
    'config-tethered-console-bin-dir (out "bin")
    'config-tethered-gui-bin-dir (out "bin")
    'config-tethered-apps-dir (out "share/applications")
    'links-file (out "share/racket/links.rktd")))
  (define (user main) (if user-layer '(#f) (list (hash-ref new-layer-config main))))
  (define config-rest (hash
    ; Previous layers' values
    'doc-search-dirs `(,@(user 'doc-dir)
                       ,(get-prev 'doc-dir)
                       ,@(get-prev-list 'doc-search-dirs))
    'lib-search-dirs `(,@(user 'lib-dir)
                       ,(get-prev 'lib-dir)
                       ,@(get-prev-list 'lib-search-dirs)
                       ,@extra-lib-dirs)
    'pkgs-search-dirs `(,@(user 'pkgs-dir)
                        ,(get-prev 'pkgs-dir)
                        ,@(get-prev-list 'pkgs-search-dirs))
    'share-search-dirs `(,@(user 'share-dir)
                         ,prev-share-dir
                         ,@(get-prev-list 'share-search-dirs))
    'include-search-dirs `(,@(user 'include-dir)
                           ,(get-prev 'include-dir)
                           ,@(get-prev-list 'include-search-dirs))
    'bin-search-dirs `(,@(user 'bin-dir)
                       ,(get-prev 'bin-dir)
                       ,@(get-prev-list 'bin-search-dirs))
    'gui-search-bin-dirs `(,@(user 'gui-bin-dir)
                           ,@(get-prev-opt 'gui-bin-dir)
                           ,@(get-prev-list 'gui-search-bin-dirs))
    'apps-search-dirs `(,@(user 'apps-dir)
                        ,(get-prev 'apps-dir)
                        ,@(get-prev-list 'apps-search-dirs))
    'man-search-dirs `(,@(user 'man-dir)
                       ,(get-prev 'man-dir)
                       ,@(get-prev-list 'man-search-dirs))
    'links-search-files `(,@(user 'links-file)
                          ,prev-links-file
                          ,@(get-prev-list 'links-search-files))

    ; Shared values between layers
    'compiled-file-roots `(same
                           ,(out "lib/racket/compiled")
                           ,@prev-compiled-file-roots)

    ; Constant values
    'absolute-installation? #t
    'build-stamp ""
    'catalogs (get-prev 'catalogs)))
  (hash-union new-layer-config config-rest))

(module+ main
  (define user-layer (make-parameter #f))
  (define lookup-lib-env (make-parameter #f))
  (define extra-lib-paths (make-parameter '()))
  (match-define (cons prev curr)
    (command-line
     #:program "generate-config"
     #:once-any
     [("--allow-user")
      "Allow package lookup in user layer"
      (user-layer #t)]
     [("--deny-user")
      "Disallow package lookup in user layer (default)"
      (user-layer #f)]
     #:once-any
     [("--lookup-lib-env")
      "Query (DY)LD_LIBRARY_PATH and add it to lib-search-dirs"
      (lookup-lib-env #t)]
     [("--no-lookup-lib-env")
      "Don't query (DY)LD_LIBRARY_PATH (default)"
      (lookup-lib-env #f)]
     #:multi
     [("--extra-lib-paths")
      libs
      "Extra native library lookup paths (separated with :)"
      (extra-lib-paths (append (extra-lib-paths) (string-split libs ":")))]
     #:args (prev-layer curr-layer)
     (cons prev-layer curr-layer)))
  (define (p path) (format "~a/~a" prev path))
  (define (o path) (format "~a/~a" curr path))
  (define (library-env-name)
    (match (system-type 'os*)
      ['linux "LD_LIBRARY_PATH"]
      ['darwin "DYLD_LIBRARY_PATH"]
      [else #f]))
  (define (library-env)
    (define res
      (when (lookup-lib-env)
        (define l (library-env-name))
        (if l
          (string-split (or (getenv l) "") ":")
          '())))
    (if (void? res) '() res))
  (pretty-write
    (make-config (call-with-input-file* prev read)
                 curr
                 (user-layer)
                 (append (extra-lib-paths) (library-env)))))
