(module lib racket
  (provide (contract-out [even? (integer? . -> . boolean?)]
			 [odd? (integer? . -> . boolean?)])))
(module gcd2 racket
   (provide (contract-out (gcd2 (integer? integer? . -> . integer?))))
   (require (submod ".." lib))
   (define (gcd2 a b)
     (cond
      [(= a 0) b]
      [(= b 0) a]
      [(and (even? a) (even? b)) (* 2 (gcd2 (/ a 2) (/ b 2)))]
      [(and (even? a) (odd? b)) (gcd2 (/ a 2) b)]
      [(and (odd? a) (even? b)) (gcd2 a (/ b 2))]
      [(and (odd? a) (odd? b) (>= a b)) (gcd2 (/ (- a b) 2) b)]
      [else (gcd2 (/ (- b a) 2) a)])))
