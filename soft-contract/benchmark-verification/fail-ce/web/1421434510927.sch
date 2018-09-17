(module foo racket
  (provide (contract-out [div2 (integer? . -> . integer?)]))
  (define (div2 n)
    (/ n 2)))
