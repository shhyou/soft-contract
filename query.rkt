#lang typed/racket

(require "lang.rkt" "closure.rkt" "utils.rkt")
(provide query handled?)

; query external solver for provability relation
(: query : .σ .V .V → .R)
(define (query σ V C)
  (cond    
    [(not (handled? C)) 'Neither] ; skip when contract is strange
    [else
     #;(printf "Queried with: ~a, ~a~n" V C)
     (let*-values ([(σ′ i) (match V
                             [(.L i) (values σ i)]
                             [(? .//? V) (values (σ-set σ -1 V) -1) #|HACK|#])]
                   [(Q* i*) (explore σ′ (set-add (span-C C) i))]
                   [(q j*) (gen i C)])
       #;(printf "premises [~a] involve labels [~a] ~n" Q* i*)
       (cond
         ; skip querying when the set of labels spanned by premises does not cover
         ; that spanned by conclusion
         [(not (subset? j* i*)) 'Neither]
         ; skip querying when could not generate conclusion
         [(false? q) 'Neither]
         [else
          (call-with
           (string-append*
            (for/list ([i i*])
              (format "~a:~a;~n"
                      (→lab i)
                      (match-let ([(.// _ C*) (σ@ σ′ i)])
                        (or (for/or: : (U #f Sym) ([C : .V C*] #:when (match? C (.// (.int?) _))) 'INT)
                            'REAL)))))
           (string-append* (for/list ([q Q*]) (format "ASSERT ~a;~n" q)))
           q)]))]))

(: handled? : .V → Bool)
(define (handled? C)
  (match? C
    (.// (.λ↓ (.λ 1 (.@ (? arith?) (list (.x 0) (or (.x _) (.b (? num?)))) _) #f) _) _)
    (.// (.λ↓ (.λ 1 (.@ (or (.=) (.equal?))
                        (list (.x 0)
                              (.@ (? arith?)
                                  (list (or (.x _) (.b (? num?)))
                                        (or (.x _) (.b (? num?)))) _)) _) #f) _) _)
    (.// (.St '¬/c (list (? handled? C′))) _)))

(: arith? : .e → Bool)
(define (arith? e)
  (match? e (.=) (.equal?) (.>) (.<) (.≥) (.≤)))

; generate all possible assertions spanned by given set of labels
; return set of assertions as wel as set of labels involved
(: explore : .σ (Setof Int) → (Values (Setof String) (Setof Int)))
(define (explore σ i*)
  (define: asserts : (Setof String) ∅)
  (define: seen : (Setof Int) ∅)
  (define: involved : (Setof Int) ∅)  
  
  (: visit : Int → Void)
  (define (visit i)
    (unless (set-member? seen i)
      (match-let ([(and V (.// U C*)) (σ@ σ i)]
                  [queue (ann ∅ (Setof Int))])
        (when (real? U)
          (∪! asserts (format "~a = ~a" (→lab i) (→lab V)))
          (∪! involved i))
        (for ([C C*])
          (let-values ([(q1 j*) (gen i C)])
            (∪! queue j*)
            (when (str? q1)
              (∪! asserts q1)
              (∪! involved j*))))
        (∪! seen i)
        (for ([j queue]) (visit j)))))
  (for ([i i*]) (visit i))
  (values asserts involved))

; generate statemetn expressing relationship between i and C
; e.g. <L0, (sum/c 1 2)>  translates to  "L0 = 1 + 2"
(: gen : Int .V → (Values (U #f String) (Setof Int)))
(define (gen i C)
  (match C
    [(.// (.λ↓ f ρ) _)
     (let ([ρ@* (match-lambda
                  [(.b (? num? n)) (Prim n)]
                  [(.x i) (ρ@ ρ (- i 1))])])
       (match f
         [(.λ 1 (.@ (? .o? o) (list (.x 0) (and e (or (.x _) (.b (? num?))))) _) #f)
          (let ([X (ρ@* e)])
            (values (format "~a ~a ~a" (→lab i) (→lab o) (→lab X))
                    (labels i X)))]
         [(.λ 1 (.@ (or (.=) (.equal?))
                    (list (.x 0) (.@ (? .o? o)
                                     (list (and M (or (.x _) (.b (? num?))))
                                           (and N (or (.x _) (.b (? num?))))) _)) _) #f)
          (let ([X (ρ@* M)] [Y (ρ@* N)])
            (values (format "~a = ~a ~a ~a" (→lab i) (→lab X) (→lab o) (→lab Y))
                    (labels i X Y)))]
         [_ (values #f ∅)]))]
    [(.// (.St '¬/c (list D)) _)
     (let-values ([(q i*) (gen i D)])
       (values (match q [(? str? s) (format "NOT (~a)" s)] [_ #f]) i*))]
    [_ (values #f ∅)]))

; perform query/ies with given declarations, assertions, and conclusion,
; trying to decide whether value definitely proves or refutes predicate
(: call-with : String String String → .R)
(define (call-with decs asserts concl)
  (match (call (str++ decs asserts (format "QUERY ~a;~n" concl)))
    [20 'Proved]
    [10 (match (call (str++ decs asserts (format "CHECKSAT ~a;" concl)))
          [20 'Refuted]
          [_ 'Neither])]
    [_ 'Neither]))

; performs system call to solver with given query
(: call : String → Int)
(define (call query)
  #;(printf "Called with:~n~a~n~n" query)
  (system/exit-code (format "echo \"~a\" | cvc4 -q > /dev/null" query)))

; generate printable/readable element for given value/label index
(: →lab : (U Int .V .o) → (U Num String Sym))
(define →lab
  (match-lambda
    [(.// (.b (? real? x)) _) x]
    [(or (.L i) (? int? i))
     (if (int? i) (if (>= i 0) (format "L~a" i) (format "X~a" (- -1 i)))
         (error "can't happen"))]
    [(.equal?) '=] [(.≥) '>=] [(.≤) '<=]
    [(? .o? o) (name o)]))

; extracts all labels in contract
(: span-C : .V → (Setof Int))
(define span-C
  (match-lambda
    [(.// (.λ↓ _ (.ρ m _)) _)
     (for/set: Int ([V (in-hash-values m)] #:when (.L? V))
       (match-let ([(.L i) V]) i))]
    [_ ∅]))

;; syntactic sugar
(define-syntax-rule (∪! s i)
  (set! s (let ([x i]) (if (set? x) (set-union s x) (set-add s i)))))
(: labels : (U .V Int) * → (Setof Int))
(define (labels . V*)
  (for/set: Int ([V V*] #:when (match? V (? int?) (.L _)))
    (match V
      [(? int? i) i]
      [(.L i) i])))

