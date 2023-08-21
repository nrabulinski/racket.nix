#lang racket

(require racket/cmdline
         racket/port
         racket/pretty
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

(define (pkg->nix name pkg cycles-table)
  (define (cycle-slave)
    (and~>> (hash-ref cycles-table name #f)
            (name->nix-ref)))
  (define (nix-expr)
    (define deps (string-dependencies pkg))
    (define master-deps
      (for/list ([dep deps])
        (or (hash-ref cycles-table dep #f)
            dep)))
    (define uniq-deps
      (for/list ([dep (list->set master-deps)]
                 #:unless (or (member dep core-dependencies)
                              (equal? name dep)))
        (name->nix-ref dep)))
    (format "{ name = \"~a\"; racketDeps = [ ~a ]; }" name (string-join uniq-deps)))
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
  (define nix-exprs
    (for/list ([(name pkg) catalog]
               #:unless (or (has-url-dependencies? pkg)
                            (member name filtered-packages)))
      (format "\"~a\" = ~a;" name (pkg->nix name pkg cycles-table))))
  (display
    (format "{}: let~nself = {~n~a~n}; in self" (string-join nix-exprs "\n"))
    out-file)
  (displayln "hello world"))
