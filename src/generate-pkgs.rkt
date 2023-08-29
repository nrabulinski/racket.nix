#lang racket

(require racket/cmdline
         racket/port
         racket/pretty
         racket/system
         racket/hash
         net/url
         graph
         threading)

; Dependencies which are always bundled with Racket which we shouldn't include
(define core-dependencies
  '("racket"
    "base"))

(define (dependency->name dep)
  (if (string? dep) dep (car dep)))

(define (simplify-name name)
  (car (string-split name "/")))

(define (dependency->root-name dep)
  (simplify-name (dependency->name dep)))

(define (string-dependencies entry [conv dependency->root-name])
  (define raw-dependencies (hash-ref entry 'dependencies '()))
  (for/list ([dep raw-dependencies]) (conv dep)))

(define (name->nix-ref name) (format "self.\"~a\"" name))

; NOTE: Both of those are global and mutable
(define pkg-sources '())
(define src-cache (make-hash))

; Strips any search parameters or query fragments from a url
(define (clean-url dirty-url)
  (struct-copy url dirty-url
               [query '()]
               [fragment #f]))

(define (try-src-cache url)
  (define (join-ref-path ref path)
    (if path
      (format "\"${~a}/~a\"" ref path)
      ref))
  (define clean (url->string (clean-url url)))
  (define path (and~> (assoc 'path (url-query url))
                      (cdr)))
  (and~> (hash-ref src-cache clean #f)
         (join-ref-path path)))

(define (nix-prefetch-url url [unpack #t])
  (define (proc-out cmd . args)
    (define exe (find-executable-path cmd))
    (define proc (apply process* exe args))
    ((fifth proc) 'wait)
    (define output (port->string (first proc)))
    (define stderr (port->string (fourth proc)))
    (close-input-port (first proc))
    (close-output-port (second proc))
    (close-input-port (fourth proc))
    (string-trim output))
  (define (to-sri hash)
    (proc-out "nix"
              "hash"
              "--extra-experimental-features" "nix-command"
              "to-sri"
              "--type" "sha256"
              hash))
  (define unpack-arg (if unpack '("--unpack") '()))
  (define hash
    (apply proc-out "nix-prefetch-url" `(,@unpack-arg ,url)))
  (to-sri hash))

(define (cache-miss url hash)
  (define (strip-dot-git path)
    (string-trim path ".git" #:left? #f))
  (define src-host (url-host url))
  (define src-path (url-path url))
  (define last-path-frag (path/param-path (last src-path)))
  (define (github-src?) (string-contains? src-host "github.com"))
  (define (gitlab-src?) (string-contains? src-host "gitlab.com"))
  (define (bitbucket-src?) (string-contains? src-host "bitbucket.org"))
  (define (srht-src?) (string-contains? src-host "sr.ht"))
  (define (zip-src?) (string-suffix? last-path-frag ".zip"))
  (define (tar-src?) (string-suffix? last-path-frag ".tar.gz"))
  (define (git-src?) (string-suffix? last-path-frag ".git"))
  (define (github-tarball-url)
    (format "https://github.com/~a/~a/archive/~a.tar.gz"
            (~> (first src-path) (path/param-path))
            (~> (second src-path)
                (path/param-path)
                (strip-dot-git))
            hash))
  (define (gitlab-tarball-url)
    (format "https://gitlab.com/~a/~a/-/archive/~a.tar.gz"
            (~> (first src-path) (path/param-path))
            (~> (second src-path)
                (path/param-path)
                (strip-dot-git))
            hash))
  (define (fetch-zip sha)
    (format #<<EOF
fetchzip {
      url = "~a";
      hash = "~a";
    }
EOF
      (url->string url)
      sha))
  (define (fetch-from from sha)
    (format #<<EOF
fetchFrom~a {
      owner = "~a";
      repo = "~a";
      rev = "~a";
      sha256 = "~a";
    }
EOF
      from
      (~> (first src-path) (path/param-path))
      (~> (second src-path) (path/param-path) (strip-dot-git))
      hash
      sha))
  (define nix-expr (cond
    [(github-src?)
      (fetch-from "GitHub"
                  (nix-prefetch-url (github-tarball-url)))]
    [(gitlab-src?)
      (fetch-from "GitLab"
                  (nix-prefetch-url (gitlab-tarball-url)))]
    [(or (zip-src?) (tar-src?))
      (fetch-zip (nix-prefetch-url (url->string url)))]
    [else
      (eprintf "URL ~a not supported yet~n" (url->string url))
      "throw \"TODO\""
      ]))
  (define src-name (url->string (clean-url url)))
  ; TODO: Some other name?
  (define nix-name src-name)
  (define nix-ref (format "sources.\"~a\"" nix-name))
  (hash-set! src-cache src-name nix-ref)
  (define nix-src
    (format #<<EOF
    "~a" = ~a;
EOF
      nix-name nix-expr))
  (set! pkg-sources (cons nix-src pkg-sources))
  (or (try-src-cache url)
      (error "Unreachable")))

(define (src->nix src hash)
  (define source-url (string->url src))
  (or (try-src-cache source-url)
      (cache-miss source-url hash)))

(define (pkg->src-nix-expr pkg source-hash)
  (define source-str (hash-ref pkg 'source))
  (define pkg-invalid? (hash-ref pkg 'checksum-error #f))
  (if pkg-invalid?
    (format "throw \"Invalid url: ~a\"" source-str)
    (src->nix source-str source-hash)))

(define (pkg->nix name pkg cycles-table catalog)
  (define (cycle-slave)
    (and~>> (hash-ref cycles-table name #f)
            (name->nix-ref)))
  (define (nix-expr)
    (define deps (string-dependencies pkg))
    (define master-deps
      (for/list ([dep (in-list deps)])
        (or (hash-ref cycles-table dep #f) dep)))
    (define uniq-deps
      (for/list ([dep (list->set master-deps)]
                 #:unless (or (member dep core-dependencies)
                              (equal? name dep)))
        (name->nix-ref dep)))
    (define cyclic-deps
      (for/list ([(slave master) cycles-table]
                 #:when (equal? master name))
        (define slave-pkg (hash-ref catalog slave))
        (define slave-hash (hash-ref slave-pkg 'checksum ""))
        (format "{ name = \"~a\"; src = ~a; checksum = \"~a\"; }"
                slave
                (pkg->src-nix-expr slave-pkg slave-hash)
                slave-hash)))
    (define source-hash (hash-ref pkg 'checksum ""))
    (format #<<EOF
mkRacketPackage {
    name = "~a";
    src = ~a;
    checksum = "~a";
    racketDeps = [ ~a ];
    cyclicDeps = [ ~a ];
  }
EOF
      name
      (pkg->src-nix-expr pkg source-hash)
      source-hash
      (string-join uniq-deps)
      (string-join cyclic-deps)))
  (or (cycle-slave) (nix-expr)))

; TODO: URL dependencies support
(define (has-url-dependencies? entry)
  (define deps (string-dependencies entry dependency->name))
  (define url-regexp #rx"https?://")
  (ormap (curry regexp-match? url-regexp) deps))
  
; NOTE: Those packages include a url dependency or depend on a package that does
(define filtered-packages
  '("qweather"
    "battlearena"
    "game-engine-style-demos"
    "vec"
    "tangerine"
    "brick-snip"
    "cultural-anthropology"
    "cmx"
    "polyglot-lib"
    "polyglot-test"
    "polyglot-doc"
    "polyglot"
    "character-creator"
    "spaceship-game-demo"
    "GUI-helpers"
    "whalesong-tools"
    "brick-tool"
    "knotty"
    "knotty-lib"
    "animal-assets"
    "json-sourcery"
    "dracula"
    "vr-assets"
    "battlearena-fortnite"))

(module+ main
  (define out-path (make-parameter #f))
  (define in-file
    (command-line
     #:program "generate-pkgs"
	 #:once-each
	 [("-o" "--output")
	  val
	  "Output path for the nix expression"
      (out-path val)]
	 #:args (in-path)
	 (open-input-file in-path)))
  (define out-file (if (out-path)
                       (open-output-file (out-path) #:exists 'replace)
                       (current-output-port)))
  (define unfiltered-catalog (read in-file))
  (define catalog
    (for/fold ([catalog unfiltered-catalog])
              ([pkg filtered-packages])
      (hash-remove catalog pkg)))
  (define edges
    (for/fold ([edges '()])
              ([(key value) catalog])
      (define deps (string-dependencies value))
      (append edges (map (curry list key) deps))))
  (define all-cycles (scc (directed-graph edges)))
  (define cycles (filter (lambda~> (length) (> 1)) all-cycles))
  (define cycles-table
    (make-immutable-hash
      (append-map
        (lambda (cycle) (~>> (cdr cycle)
                             (map (lambda~> (cons (car cycle))))))
        cycles)))
  (fprintf out-file "{fetchFromGitHub, fetchFromGitLab, fetchzip}: let~n  self = {~n")
  (define (package-filter pkg)
    (or (has-url-dependencies? pkg)
        (member (hash-ref pkg 'name) filtered-packages)))
  (define packages-list
    (~>> (hash-values catalog)
         (filter-not package-filter)))
  (for/async ([pkg (in-list packages-list)])
    (define name (hash-ref pkg 'name))
    (fprintf out-file "\"~a\" = ~a;~n" name (pkg->nix name pkg cycles-table catalog)))
  (fprintf out-file "};~n  sources = {~n~a~n}; in self" (string-join pkg-sources "\n")))
