#lang racket/base
(require racket/match racket/port
         "utils.rkt"
         (only-in "check.rkt" feedback)
         (only-in redex/reduction-semantics variable-not-in)
         (for-syntax racket/base racket/match))
(provide (rename-out [module-begin #%module-begin]
                     [top-interaction #%top-interaction])
         feedback/massage
         #%app #%datum #%top
         read read-syntax)

(define-syntax-rule (module-begin m ...)
  (#%module-begin (parameterize ([verify-top? #f])
                    (feedback/massage '(m ...)))))

(define-syntax-rule (top-interaction . x)
  (#%top-interaction . (parameterize ([verify-top? #f])
                         (feedback/massage 'x))))

#;(define-syntax-rule (top-interaction . e)
  (#%top-interaction . (begin #;(log-debug "Run Top:~n~a~n" (massage-top 'e))
                              (feedback (massage-top 'e)))))

(define (feedback/massage x [timeout 30])
  #;(log-debug "Prog:~n~a~n" (pretty (massage x)))
  (log-info "feedback/massage ... ~a" (current-process-milliseconds))
  (begin0
      (feedback (massage x) timeout)
    (log-info "Finished feedback/massage: ~a" (current-process-milliseconds))))

(define verify-top? (make-parameter #f))

;; Havoc each exported identifier
(define (massage p)
  (match p
    ;; Given list of modules without top-level, insert top-level havoc-ing everybody
    [(list (and modl `(module ,m racket ,dss ...)) ...)
     (define names
       (for*/fold ([acc '()]) ([ds dss] [d ds])
         (append #|bad but not too bad|# (collect-names d) acc)))
     `(,@modl
       (require ,@(for/list ([mᵢ m]) `(quote ,mᵢ)))
       (amb ,@(for/list ([x names]) `(• ,x))))]
    ;; Given list of modules followed by top-level,
    ;; either leave as-is or also verify top-level depending on `(verify-top?)`
    [(list (and modl `(module ,_ racket ,_ ...)) ... `(require ,x ...) e ...)
     (cond
      [(verify-top?)
       (define top-level (variable-not-in modl 'top-level))
       (massage
        `(,@modl
          (module ,top-level racket
            (provide (contract-out [,top-level any/c]))
            (require ,@(for/list ([xᵢ x]) `(submod ".." ,(cadr xᵢ))))
            (define (,top-level) (begin ,@e)))))]
      [else p])]
    [(list (and modl `(module ,_ racket ,_ ...)) ... e ...)
     (massage `(,@modl (require) ,@e))]
    [(and m `(module ,_ racket ,_ ...)) (massage (list m))]
    [e (list e)]))

(define collect-names
  (match-lambda
   [(or `(provide/contract [,x ,_] ...)
        `(provide (contract-out [,x ,_] ...)))
    x]
   [_ '()]))