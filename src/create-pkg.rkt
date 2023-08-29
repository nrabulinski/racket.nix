#lang racket/base

(require racket/cmdline
         racket/hash
         racket/pretty)

(module+ main
  (define checksum (make-parameter #f))
  (define pkg-source
    (command-line
     #:program "generate-config"
     #:once-each
     [("-c" "--checksum")
      c
      "Package checksum"
      (checksum c)]
     #:args (source)
     source))
  (unless (checksum)
    (error "Checksum is required"))
  (define pkg (hash
    'source pkg-source
    'checksum (checksum)))
  (pretty-write pkg))
