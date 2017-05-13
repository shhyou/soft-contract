#lang typed/racket/base

(provide app@)

(require racket/set
         racket/match
         (only-in racket/list split-at)
         typed/racket/unit
         syntax/parse/define
         set-extras
         "../utils/main.rkt"
         "../ast/main.rkt"
         "../runtime/main.rkt"
         "../signatures.rkt"
         "signatures.rkt")

(define-unit app@
  (import mon^ compile^ kont^ proof-system^ prims^ memoize^ widening^)
  (export app^)

  (: app : -$ -ℒ -W¹ (Listof -W¹) -Γ -⟪ℋ⟫ -Σ -⟦k⟧ → (℘ -ς))
  (define (app $ ℒ Wₕ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)
    #;(when (match? Wₕ (-W¹ (-● (== (set 'procedure?))) _))
        (printf "app: ~a to ~a~n" (show-W¹ Wₕ) (map show-W¹ Wₓs)))
    (match-define (-Σ σ σₖ M) Σ)
    (match-define (-W¹ Vₕ sₕ) Wₕ)
    (define l (ℓ-src (-ℒ-app ℒ)))

    (: blm-arity : Arity Natural → -blm)
    (define (blm-arity required provided)
      ;; HACK for error message. Probably no need to fix
      (define msg (format-symbol "require ~a arguments"
                                 (string->symbol (format "~a" required))))
      (-blm l 'Λ (list msg) (map -W¹-V Wₓs) (-ℒ-app ℒ)))

    (define-syntax-rule (with-guarded-arity a* e ...)
      (let ([n (length Wₓs)]
            [a a*])
        (cond
          [(arity-includes? a n) e ...]
          [else (⟦k⟧ (blm-arity a n) $ Γ ⟪ℋ⟫ Σ)])))

    (define (app-And/C [W₁ : -W¹] [W₂ : -W¹]) : (℘ -ς)
      (define ⟦rhs⟧ (mk-app ℒ (mk-rt W₂) (list (mk-rt (car Wₓs)))))
      (app $ ℒ W₁ Wₓs Γ ⟪ℋ⟫ Σ (and∷ l (list ⟦rhs⟧) ⊥ρ ⟦k⟧)))

    (define (app-Or/C [W₁ : -W¹] [W₂ : -W¹]) : (℘ -ς)
      (define ⟦rhs⟧ (mk-app ℒ (mk-rt W₂) (list (mk-rt (car Wₓs)))))
      (app $ ℒ W₁ Wₓs Γ ⟪ℋ⟫ Σ (or∷ l (list ⟦rhs⟧) ⊥ρ ⟦k⟧)))
    
    (define (app-Not/C [Wᵤ : -W¹]) : (℘ -ς)
      (app $ ℒ Wᵤ Wₓs Γ ⟪ℋ⟫ Σ (neg∷ l ⟦k⟧)))

    (define (app-One-Of/C [bs : (Listof Base)]) : (℘ -ς)
      (match-define (list (-W¹ Vₓ sₓ)) Wₓs)
      (define Wₐ
        (case (sat-one-of Vₓ bs)
          [(✓) -tt.W]
          [(✗) -ff.W]
          [(?) (-W -Bool.Vs (?t@ (-One-Of/C bs) sₓ))]))
      (⟦k⟧ Wₐ $ Γ ⟪ℋ⟫ Σ))

    (define (app-St/C [𝒾 : -𝒾] [W-Cs : (Listof -W¹)]) : (℘ -ς)
      ;; TODO fix ℓ
      (match-define (list Wₓ) Wₓs)
      (match-define (-W¹ Vₓ _) Wₓ)
      (match Vₓ
        [(or (-St (== 𝒾) _) (-St* (-St/C _ (== 𝒾) _) _ _))
         (define ⟦chk-field⟧s : (Listof -⟦e⟧)
           (for/list ([W-C (in-list W-Cs)]
                      [i (in-naturals)] #:when (index? i))
             (define Ac (let ([ac (-st-ac 𝒾 i)]) (-W¹ ac ac)))
             (mk-app ℒ (mk-rt W-C)
                         (list (mk-app ℒ (mk-rt Ac) (list (mk-rt Wₓ)))))))
         (define P (let ([p (-st-p 𝒾)]) (-W¹ p p)))
         (app $ ℒ P (list Wₓ) Γ ⟪ℋ⟫ Σ (and∷ l ⟦chk-field⟧s ⊥ρ ⟦k⟧))]
        [_
         (⟦k⟧ -ff.W $ Γ ⟪ℋ⟫ Σ)]))

    (match Vₕ
      ;; In the presence of struct contracts, field accessing is not an atomic operation
      ;; because structs can be contract-wrapped arbitrarily deeply,
      ;; plus contracts can be arbitrary code.
      ;; This means field accessing cannot be implemented in `δ`
      [(-st-p  𝒾) ((app-st-p 𝒾) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)]
      [(-st-mk 𝒾) ((app-st-mk 𝒾) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)]
      [(-st-ac  𝒾 i) ((app-st-ac  𝒾 i) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)]
      [(-st-mut 𝒾 i) ((app-st-mut 𝒾 i) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)]
      ['apply (app-apply $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)]
      ['make-sequence (app-make-sequence $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)]

      ;; Regular stuff
      [(? symbol? o) ((app-prim o) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)]
      [(-Clo xs ⟦e⟧ ρₕ Γₕ)
       (with-guarded-arity (shape xs)
         ((app-clo xs ⟦e⟧ ρₕ Γₕ sₕ) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧))]
      [(-Case-Clo clauses ρₕ Γₕ)
       ((app-Case-Clo clauses ρₕ Γₕ sₕ) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)]
      [(-Ar C α l³)
       (with-guarded-arity (guard-arity C)
         (define-values (c _) (-ar-split sₕ))
         (cond
           [(-=>? C)
            (for/union : (℘ -ς) ([Vᵤ (σ@ σ α)] #:unless (equal? Vₕ Vᵤ))
                       ((app-Ar C c Vᵤ sₕ l³) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧))]
           [(-=>i? C)
            (for/union : (℘ -ς) ([Vᵤ (σ@ σ α)] #:unless (equal? Vₕ Vᵤ))
                       ((app-Indy C c Vᵤ sₕ l³) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧))]
           [else
            (for/union : (℘ -ς) ([Vᵤ (σ@ σ α)] #:unless (equal? Vₕ Vᵤ))
                       ((app-guarded-Case C c Vᵤ sₕ l³) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧))]))]
      [(-And/C #t (-⟪α⟫ℓ α₁ ℓ₁) (-⟪α⟫ℓ α₂ ℓ₂))
       (with-guarded-arity 1
         (match-define (list c₁ c₂) (-app-split 'and/c sₕ 2))
         (for*/union : (℘ -ς) ([C₁ (σ@ σ α₁)] [C₂ (σ@ σ α₂)])
                     (app-And/C (-W¹ C₁ c₁) (-W¹ C₂ c₂))))]
      [(-Or/C #t (-⟪α⟫ℓ α₁ ℓ₁) (-⟪α⟫ℓ α₂ ℓ₂))
       (with-guarded-arity 1
         (match-define (list c₁ c₂) (-app-split 'or/c sₕ 2))
         (for*/union : (℘ -ς) ([C₁ (σ@ σ α₁)] [C₂ (σ@ σ α₂)])
                     (app-Or/C (-W¹ C₁ c₁) (-W¹ C₂ c₂))))]
      [(-Not/C (-⟪α⟫ℓ α ℓ*))
       (with-guarded-arity 1
         (match-define (list c*) (-app-split 'not/c sₕ 1))
         (for/union : (℘ -ς) ([C* (σ@ σ α)])
                    (app-Not/C (-W¹ C* c*))))]
      [(-One-Of/C vals)
       (with-guarded-arity 1
         (app-One-Of/C vals))]
      [(-St/C #t s αℓs)
       (with-guarded-arity 1
         (define-values (αs ℓs) (unzip-by -⟪α⟫ℓ-addr -⟪α⟫ℓ-loc αℓs))
         (define cs (-struct/c-split sₕ s))
         (for/union : (℘ -ς) ([Cs (σ@/list σ αs)])
                    (app-St/C s (map -W¹ Cs cs))))]
      [(-● _) ;; TODO clean this mess up

       (define-values (ℓ l) (unpack-ℒ ℒ))

       (: blm : -V → -Γ → (℘ -ς))
       (define ((blm C) Γ)
         (define blm (-blm l 'Λ (list C) (list Vₕ) (-ℒ-app ℒ)))
         (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ))

       (: chk-arity : -Γ → (℘ -ς))
       (define (chk-arity Γ)
         (define required-arity
           (let ([b (-b (length Wₓs))])
             (-W¹ b b)))
         (define Wₕ-arity
           (let ([Vₐ (V-arity Vₕ)]
                 [sₐ (?t@ 'procedure-arity sₕ)])
             (-W¹ (if Vₐ (-b Vₐ) -●.V) sₐ)))
         (with-MΓ+/-oW (M σ Γ 'arity-includes? Wₕ-arity required-arity)
           #:on-t do-app
           #:on-f (blm (format-symbol "(arity-includes/c ~a)" (length Wₓs)))))

       (: do-app : -Γ → (℘ -ς))
       (define (do-app Γ)
         ((app-opq sₕ) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧))
       
       (with-MΓ+/-oW (M σ Γ 'procedure? Wₕ)
         #:on-t chk-arity
         #:on-f (blm 'procedure?))]
      [_
       (define blm (-blm l 'Λ (list 'procedure?) (list Vₕ) (-ℒ-app ℒ)))
       (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ)]))

  (: app-prim : Symbol → -⟦f⟧)
  (define (app-prim o)
    (λ ($ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)
      (match (get-prim o)
        [(-⟦o⟧.boxed ⟦o⟧)
         (match-define (-Γ _ as₀) Γ)
         #;(begin
             (printf "~a ~a~n" (show-o o) (map show-W¹ Wₓs))
             (for ([ans (in-set (⟦o⟧ ⟪ℋ⟫ ℓ Σ Γ Wₓs))])
               (printf "  - ~a~n" (show-ΓA ans)))
             (printf "~n"))
         (for/union : (℘ -ς) ([ΓA (in-set (⟦o⟧ ⟪ℋ⟫ ℒ Σ Γ Wₓs))])
                    (match-define (-ΓA φs A) ΓA)
                    (⟦k⟧ A $ (-Γ φs as₀) ⟪ℋ⟫ Σ))]
        [(-⟦f⟧.boxed ⟦f⟧)
         (⟦f⟧ $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)])))

  (: app-clo : -formals -⟦e⟧ -ρ -Γ -?t → -⟦f⟧)
  (define (app-clo xs ⟦e⟧ ρₕ Γₕ sₕ)
    (λ ($ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)
      (define-values (Vₓs sₓs) (unzip-by -W¹-V -W¹-t Wₓs))

      (define plausible? ; conservative `plausible?` to filter out some
        #t #;(cond [sₕ
                    (for/and : Boolean ([γ (in-list (-Γ-tails Γ))])
                      (match-define (-γ αₖ _ sₕ* _) γ)
                      (cond [(equal? sₕ sₕ*)
                             (and (-ℬ? αₖ) (equal? (-ℬ-exp αₖ) ⟦e⟧))]
                            [else #t]))]
                   [else #t]))

      (cond
        [plausible?
         (define ⟪ℋ⟫ₑₑ (⟪ℋ⟫+ ⟪ℋ⟫ (-edge ⟦e⟧ ℒ)))
         ;; Target's environment
         (define ρ* : -ρ
           (match xs
             [(? list? xs)
              (alloc-init-args! Σ Γ ρₕ ⟪ℋ⟫ₑₑ sₕ xs Wₓs)]
             [(-var zs z)
              (define-values (Ws₀ Wsᵣ) (split-at Wₓs (length zs)))
              (define ρ₀ (alloc-init-args! Σ Γ ρₕ ⟪ℋ⟫ₑₑ sₕ zs Ws₀))
              (define Vᵣ (alloc-rest-args! Σ Γ ⟪ℋ⟫ₑₑ ℒ Wsᵣ))
              (define αᵣ (-α->⟪α⟫ (-α.x z ⟪ℋ⟫ₑₑ #|TODO|# ∅)))
              (σ⊕V! Σ αᵣ Vᵣ)
              (ρ+ ρ₀ z αᵣ)]))

         (define Γₕ*
           (let ([fvs (if (or (-λ? sₕ) (-case-λ? sₕ)) (fvₜ sₕ) ∅eq)])
             (inv-caller->callee (-Σ-σ Σ) fvs xs Wₓs Γ Γₕ)))

         (define αₖ (-ℬ xs ⟦e⟧ ρ*))
         (define κ (-κ (memoize-⟦k⟧ ⟦k⟧) Γ ⟪ℋ⟫ sₓs))
         (σₖ⊕! Σ αₖ κ)
         {set (-ς↑ αₖ Γₕ* ⟪ℋ⟫ₑₑ)}]
        [else ∅])))

  #;(: apply-app-clo : (-var Symbol) -⟦e⟧ -ρ -Γ -?t → -$ -ℒ (Listof -W¹) -W¹ -Γ -⟪ℋ⟫ -Σ -⟦k⟧ → (℘ -ς))
  #;(define ((apply-app-clo xs ⟦e⟧ ρₕ Γₕ sₕ) $ ℒ Ws₀ Wᵣ Γ ⟪ℋ⟫ Σ ⟦k⟧)
    (match-define (-var xs₀ xᵣ) xs)
    (define ⟪ℋ⟫ₑₑ (⟪ℋ⟫+ ⟪ℋ⟫ (-edge ⟦e⟧ ℒ)))
    (match-define (-W¹ Vᵣ sᵣ) Wᵣ)
    (define ρ*
      (let ([ρ₀ (alloc-init-args! Σ Γ ρₕ ⟪ℋ⟫ₑₑ sₕ xs₀ Ws₀)])
        (define αᵣ (-α->⟪α⟫ (-α.x xᵣ ⟪ℋ⟫ₑₑ (predicates-of-W (-Σ-σ Σ) Γ Wᵣ))))
        (σ⊕! Σ Γ αᵣ Wᵣ)
        (ρ+ ρ₀ xᵣ αᵣ)))
    (define αₖ (-ℬ xs ⟦e⟧ ρ* #;(-Γ-facts #|TODO|#Γₕ)))
    (define κ
      (let ([ss₀ (map -W¹-t Ws₀)]
            [sᵣ (-W¹-t Wᵣ)])
        (-κ (memoize-⟦k⟧ ⟦k⟧) Γ ⟪ℋ⟫ `(,sₕ ,@ss₀ ,sᵣ))))
    (σₖ⊕! Σ αₖ κ)
    {set (-ς↑ αₖ Γₕ ⟪ℋ⟫ₑₑ)})

  (: app-Case-Clo : (Listof (Pairof (Listof Symbol) -⟦e⟧)) -ρ -Γ -?t → -⟦f⟧)
  (define ((app-Case-Clo clauses ρₕ Γₕ sₕ) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)
    (define n (length Wₓs))
    (define clause
      (for/or : (Option (Pairof (Listof Symbol) -⟦e⟧)) ([clause clauses])
        (match-define (cons xs _) clause)
        (and (equal? n (length xs)) clause)))
    (cond
      [clause
       (match-define (cons xs ⟦e⟧) clause)
       ((app-clo xs ⟦e⟧ ρₕ Γₕ sₕ) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)]
      [else
       (define a : (Listof Index) (for/list ([clause clauses]) (length (car clause))))
       (define-values (ℓ l) (unpack-ℒ ℒ))
       (define blm (-blm l 'Λ
                         (list (format-symbol "arity in ~a" (string->symbol (format "~a" a))))
                         (map -W¹-V Wₓs) ℓ))
       (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ)]))

  (: app-guarded-Case : -V -?t -V -?t -l³ → -⟦f⟧)
  (define ((app-guarded-Case C c Vᵤ sₕ l³) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)
    (error 'app-guarded-Case "TODO"))

  (: app-Ar : -=> -?t -V -?t -l³ → -⟦f⟧)
  (define ((app-Ar C c Vᵤ sₕ l³) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)
    (match-define (-l³ l+ l- lo) l³)
    (define Wᵤ (-W¹ Vᵤ sₕ)) ; inner function
    (match-define (-=> αℓs Rng _) C)
    (define-values (cs d) (-->-split c (shape αℓs)))
    (match-define (-Σ σ _ _) Σ)
    (define l³* (-l³ l- l+ lo))
    (define ⟦k⟧/mon-rng (mon*.c∷ l³ ℒ Rng d ⟦k⟧))
    (match* (αℓs cs)
      [('() '()) ; no arg
       (app $ (ℒ-with-l ℒ 'app-Ar) Wᵤ '() Γ ⟪ℋ⟫ Σ ⟦k⟧/mon-rng)]
      [((? pair?) (? pair?))
       (define-values (αs ℓs) (unzip-by -⟪α⟫ℓ-addr -⟪α⟫ℓ-loc αℓs))
       (for*/union : (℘ -ς) ([Cs (in-set (σ@/list σ αs))])
         (match-define (cons ⟦mon-x⟧ ⟦mon-x⟧s)
           (for/list : (Listof -⟦e⟧) ([C Cs]
                                      [c cs]
                                      [Wₓ Wₓs]
                                      [ℓₓ : ℓ ℓs])
             (mk-mon l³* (ℒ-with-mon ℒ ℓₓ) (mk-rt (-W¹ C c)) (mk-rt Wₓ))))
         (⟦mon-x⟧ ⊥ρ $ Γ ⟪ℋ⟫ Σ
          (ap∷ (list Wᵤ) ⟦mon-x⟧s ⊥ρ (ℒ-with-l ℒ 'app-Ar)
               ⟦k⟧/mon-rng)))]
      [((-var αℓs₀ αℓᵣ) (-var cs₀ cᵣ))
       (define-values (αs₀ ℓs₀) (unzip-by -⟪α⟫ℓ-addr -⟪α⟫ℓ-loc αℓs₀))
       (match-define (-⟪α⟫ℓ αᵣ ℓᵣ) αℓᵣ)
       (define-values (Ws₀ Wsᵣ) (split-at Wₓs (length αs₀)))
       (define Vᵣ (alloc-rest-args! Σ Γ ⟪ℋ⟫ (ℒ-with-mon ℒ ℓᵣ) Wsᵣ))
       (define Wᵣ (-W¹ Vᵣ (-?list (map -W¹-t Wsᵣ))))
       (for*/union : (℘ -ς) ([Cs₀ (in-set (σ@/list σ αs₀))]
                             [Cᵣ (in-set (σ@ σ αᵣ))])
         (define ⟦mon-x⟧s : (Listof -⟦e⟧)
           (for/list ([Cₓ Cs₀] [cₓ cs₀] [Wₓ Ws₀] [ℓₓ : ℓ ℓs₀])
             (mk-mon l³* (ℒ-with-mon ℒ ℓₓ) (mk-rt (-W¹ Cₓ cₓ)) (mk-rt Wₓ))))
         (define ⟦mon-x⟧ᵣ : -⟦e⟧
           (mk-mon l³* (ℒ-with-mon ℒ ℓᵣ) (mk-rt (-W¹ Cᵣ cᵣ)) (mk-rt Wᵣ)))
         (match ⟦mon-x⟧s
           ['()
            (⟦mon-x⟧ᵣ ⊥ρ $ Γ ⟪ℋ⟫ Σ
             (ap∷ (list Wᵤ -apply.W¹) '() ⊥ρ (ℒ-with-l ℒ 'app-Ar) ⟦k⟧/mon-rng))]
           [(cons ⟦mon-x⟧₀ ⟦mon-x⟧s*)
            (⟦mon-x⟧₀ ⊥ρ $ Γ ⟪ℋ⟫ Σ
             (ap∷ (list Wᵤ -apply.W¹) `(,@ ⟦mon-x⟧s* ,⟦mon-x⟧ᵣ) ⊥ρ (ℒ-with-l ℒ 'app-Ar)
                  ⟦k⟧/mon-rng))]))]))

  #;(: apply-app-Ar : (-=> -?t -V -?t -l³ → -$ -ℒ (Listof -W¹) -W¹ -Γ -⟪ℋ⟫ -Σ -⟦k⟧ → (℘ -ς)))
  #;(define ((apply-app-Ar C c Vᵤ sₕ l³) $ ℒ Ws₀ Wᵣ Γ ⟪ℋ⟫ Σ ⟦k⟧)
    (match-define (-=> (-var αℓs₀ (-⟪α⟫ℓ αᵣ ℓᵣ)) (-⟪α⟫ℓ β ℓₐ) _) C)
    (match-define-values ((-var cs₀ cᵣ) d) (-->-split c (arity-at-least (length αℓs₀))))
    ;; FIXME copied n pasted from app-Ar
    (define-values (αs₀ ℓs₀) (unzip-by -⟪α⟫ℓ-addr -⟪α⟫ℓ-loc αℓs₀))
    (match-define (-W¹ Vᵣ sᵣ) Wᵣ)
    (match-define (-l³ l+ l- lo) l³)
    (define l³* (-l³ l- l+ lo))
    (define Wᵤ (-W¹ Vᵤ sₕ))
    (for*/union : (℘ -ς) ([Cs₀ (in-set (σ@/list Σ αs₀))]
                          [Cᵣ (in-set (σ@ Σ αᵣ))]
                          [D (in-set (σ@ Σ β))])
      (define ⟦mon-x⟧s : (Listof -⟦e⟧)
        (for/list ([Cₓ Cs₀] [cₓ cs₀] [Wₓ Ws₀] [ℓₓ : ℓ ℓs₀])
          (mk-mon l³* (ℒ-with-mon ℒ ℓₓ) (mk-rt (-W¹ Cₓ cₓ)) (mk-rt Wₓ))))
      (define ⟦mon-x⟧ᵣ : -⟦e⟧
        (mk-mon l³* (ℒ-with-mon ℒ ℓᵣ) (mk-rt (-W¹ Cᵣ cᵣ)) (mk-rt Wᵣ)))
      (match ⟦mon-x⟧s
        ['()
         (⟦mon-x⟧ᵣ ⊥ρ $ Γ ⟪ℋ⟫ Σ
          (ap∷ (list Wᵤ -apply.W¹) '() ⊥ρ ℒ
               (mon.c∷ l³ (ℒ-with-mon ℒ ℓₐ) (-W¹ D d) ⟦k⟧)))]
        [(cons ⟦mon-x⟧₀ ⟦mon-x⟧s*)
         (⟦mon-x⟧₀ ⊥ρ $ Γ ⟪ℋ⟫ Σ
          (ap∷ (list Wᵤ -apply.W¹) `(,@ ⟦mon-x⟧s* ,⟦mon-x⟧ᵣ) ⊥ρ ℒ
               (mon.c∷ l³ (ℒ-with-mon ℒ ℓₐ) (-W¹ D d) ⟦k⟧)))])))

  (: app-Indy : -=>i -?t -V -?t -l³ → -⟦f⟧)
  (define ((app-Indy C c Vᵤ sₕ l³) $ ℒ Wₓs Γ ⟪ℋ⟫ Σ ⟦k⟧)
    (match-define (-l³ l+ l- lo) l³)
    (define l³* (-l³ l- l+ lo))
    (define Wᵤ (-W¹ Vᵤ sₕ)) ; inner function
    (match-define (-=>i αℓs (list Mk-D mk-d ℓᵣ) _) C)
    (match-define (-Clo xs ⟦d⟧ ρᵣ _) Mk-D)
    (define W-rng (-W¹ Mk-D mk-d))
    (define-values (αs ℓs) (unzip-by -⟪α⟫ℓ-addr -⟪α⟫ℓ-loc αℓs))
    (define-values (cs _) (-->i-split c (length αℓs)))

    (match xs
      [(? list?)
       (define ⟦x⟧s : (Listof -⟦e⟧) (for/list ([x (in-list xs)]) (↓ₓ lo x)))
       (define ⟦app⟧ (mk-app (ℒ-with-l ℒ 'app-Indy) (mk-rt Wᵤ) ⟦x⟧s))
       (define ⟦rng⟧
         (cond [(-λ? mk-d) (assert (equal? xs (-λ-_0 mk-d))) ⟦d⟧]
               [else (mk-app (ℒ-with-l ℒ 'app-Indy) (mk-rt W-rng) ⟦x⟧s)]))
       (define ⟦mon-app⟧ (mk-mon l³ (ℒ-with-mon ℒ ℓᵣ) ⟦rng⟧ ⟦app⟧))
       (define ρᵣ* : -ρ (if (-λ? mk-d) ρᵣ ⊥ρ))
       (for/union : (℘ -ς) ([Cs (in-set (σ@/list Σ αs))])
         (define ⟦mon-x⟧s : (Listof -⟦e⟧)
           (for/list ([C (in-list Cs)]
                      [c (in-list cs)]
                      [Wₓ (in-list Wₓs)]
                      [ℓₓ : ℓ (in-list ℓs)])
             (mk-mon l³* (ℒ-with-mon ℒ ℓₓ) (mk-rt (-W¹ C c)) (mk-rt Wₓ))))
         (match* (xs ⟦x⟧s ⟦mon-x⟧s)
           [('() '() '())
            (⟦mon-app⟧ ρᵣ* $ Γ ⟪ℋ⟫ Σ ⟦k⟧)]
           [((cons x xs*) (cons ⟦x⟧ ⟦x⟧s*) (cons ⟦mon-x⟧ ⟦mon-x⟧s*))
            (⟦mon-x⟧ ρᵣ* $ Γ ⟪ℋ⟫ Σ
             (let∷ (-ℒ-app ℒ)
                   (list x)
                   (for/list ([xᵢ (in-list xs*)] [⟦mon⟧ᵢ (in-list ⟦mon-x⟧s*)])
                     (cons (list xᵢ) ⟦mon⟧ᵢ))
                   '()
                   ⟦mon-app⟧
                   ρᵣ*
                    ⟦k⟧))]))]
      [(-var zs z)
       (error 'app-Indy "TODO: varargs in ->i: ~a" (cons zs z))]))

  (define (app-st-p [𝒾 : -𝒾]) : -⟦f⟧
    (define st-p (-st-p 𝒾))
    (λ ($ ℒ Ws Γ ⟪ℋ⟫ Σ ⟦k⟧)
      (match Ws
        [(list (and W (-W¹ _ s)))
         (match-define (-Σ σ _ M) Σ)
         (define sₐ (?t@ st-p s))
         (define A
           (case (MΓ⊢oW M σ Γ st-p W)
             [(✓) -tt.Vs]
             [(✗) -ff.Vs]
             [(?) -Bool.Vs]))
         (⟦k⟧ (-W A sₐ) $ Γ ⟪ℋ⟫ Σ)]
        [_
         (define blm (blm-arity (-ℒ-app ℒ) (show-o st-p) 1 (map -W¹-V Ws)))
         (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ)])))

  (define (app-st-mk [𝒾 : -𝒾]) : -⟦f⟧
    (define st-mk (-st-mk 𝒾))
    (define n (get-struct-arity 𝒾))
    (λ ($ ℒ Ws Γ ⟪ℋ⟫ Σ ⟦k⟧)
      (cond
        [(= n (length Ws))
         (match-define (-Σ σ _ M) Σ)
         (define sₐ (apply ?t@ st-mk (map -W¹-t Ws)))
         (define αs : (Listof ⟪α⟫)
           (for/list ([i : Index n])
             (-α->⟪α⟫ (-α.fld 𝒾 ℒ ⟪ℋ⟫ i))))
         (for ([α : ⟪α⟫ αs] [W (in-list Ws)])
           (σ⊕! Σ Γ α W))
         (define V (-St 𝒾 αs))
         (⟦k⟧ (-W (list V) sₐ) $ Γ ⟪ℋ⟫ Σ)]
        [else
         (define blm (blm-arity (-ℒ-app ℒ) (show-o st-mk) n (map -W¹-V Ws)))
         (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ)])))

  (define (app-st-ac [𝒾 : -𝒾] [i : Index]) : -⟦f⟧
    (define ac (-st-ac 𝒾 i))
    (define p  (-st-p 𝒾))
    (define n (get-struct-arity 𝒾))
    
    (: ⟦ac⟧ : -⟦f⟧)
    (define (⟦ac⟧ $ ℒ Ws Γ ⟪ℋ⟫ Σ ⟦k⟧)
      (match Ws
        [(list (and W (-W¹ V s)))
         (define-values (ℓ l) (unpack-ℒ ℒ))
         (define (blm) (-blm l (show-o ac) (list p) (list V) ℓ))
         (match-define (-Σ σ _ M) Σ)
         (match V
           [(-St (== 𝒾) αs)
            (define α (list-ref αs i))
            (define sₐ (and (not (mutated? σ α)) (?t@ ac s)))
            (cond
              [($@ $ sₐ) =>
               (λ ([V : -V])
                 (cond [(plausible-V-t? (-Γ-facts Γ) V sₐ)
                        (define $* ($+ $ sₐ V))
                        (⟦k⟧ (-W (list V) sₐ) $* Γ ⟪ℋ⟫ Σ)]
                       [else ∅]))]
              [else
               (define Vs (σ@ σ α))
               (for/union : (℘ -ς) ([V Vs])
                          (cond [(plausible-V-t? (-Γ-facts Γ) V sₐ)
                                 (define $* ($+ $ sₐ V))
                                 (⟦k⟧ (-W (list V) sₐ) $* Γ ⟪ℋ⟫ Σ)]
                                [else ∅]))])]
           [(-St* (-St/C _ (== 𝒾) αℓs) α l³)
            (match-define (-l³ _ _ lₒ) l³)
            (define Ac (-W¹ ac ac))
            (cond
              ;; mutable field should be wrapped
              [(struct-mutable? 𝒾 i)
               (match-define (-⟪α⟫ℓ αᵢ ℓᵢ) (list-ref αℓs i))
               (define Cᵢs (σ@ σ αᵢ))
               (define Vs  (σ@ σ α))
               (define cᵢ #f #;(⟪α⟫->s αᵢ))
               (define ℒ*
                 (match-let ([(-ℒ ℓs ℓ) ℒ])
                   (-ℒ ℓs (match-let ([(loc src l c i) (ℓ->loc ℓ)])
                            (loc->ℓ (loc 'Λ l c i))))))
               (for*/union : (℘ -ς) ([Cᵢ (in-set Cᵢs)] [V* (in-set Vs)])
                           (⟦ac⟧ $ ℒ (list (-W¹ V* s)) Γ ⟪ℋ⟫ Σ
                            (mon.c∷ l³ (ℒ-with-mon ℒ* ℓᵢ) (-W¹ Cᵢ cᵢ) ⟦k⟧)))]
              ;; no need to check immutable field
              [else
               ;; TODO: could this loop forever due to cycle?
               (for/union : (℘ -ς) ([V* (in-set (σ@ σ α))])
                          (⟦ac⟧ $ ℒ (list (-W¹ V* s)) Γ ⟪ℋ⟫ Σ ⟦k⟧))])]
           [(-● ps)
            (with-Γ+/- ([(Γₒₖ Γₑᵣ) (MΓ+/-oW M σ Γ p W)])
              #:true  (⟦k⟧ (-W (if (and (equal? 𝒾 -𝒾-cons) (equal? i 1) (∋ ps 'list?))
                                   (list (-● {set 'list?}))
                                   -●.Vs)
                               (?t@ ac s))
                       $ Γₒₖ ⟪ℋ⟫ Σ)
              #:false (⟦k⟧ (blm) $ Γₑᵣ ⟪ℋ⟫ Σ))]
           [_ (⟦k⟧ (blm) $ Γ ⟪ℋ⟫ Σ)])]
        [_
         (define blm (blm-arity (-ℒ-app ℒ) (show-o ac) 1 (map -W¹-V Ws)))
         (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ)]))
    ⟦ac⟧)

  (define (app-st-mut [𝒾 : -𝒾] [i : Index]) : -⟦f⟧
    (define mut (-st-mut 𝒾 i))
    (define p (-st-p 𝒾))
    
    (: ⟦mut⟧ : -⟦f⟧)
    (define (⟦mut⟧ $ ℒ Ws Γ ⟪ℋ⟫ Σ ⟦k⟧)
      (match Ws
        [(list Wₛ Wᵥ)
         (match-define (-Σ σ _ M) Σ)
         (match-define (-W¹ Vₛ sₛ) Wₛ)
         (match-define (-W¹ Vᵥ _ ) Wᵥ)
         (define-values (ℓ l) (unpack-ℒ ℒ))
         (define (blm)
           (-blm l (show-o mut) (list p) (list Vₛ) ℓ))
         
         (match Vₛ
           [(-St (== 𝒾) αs)
            (define α (list-ref αs i))
            (σ⊕! Σ Γ α Wᵥ #:mutating? #t)
            (⟦k⟧ -void.W $ Γ ⟪ℋ⟫ Σ)]
           [(-St* (-St/C _ (== 𝒾) γℓs) α l³)
            (match-define (-l³ l+ l- lo) l³)
            (define l³* (-l³ l- l+ lo))
            (match-define (-⟪α⟫ℓ γ ℓᵢ) (list-ref γℓs i))
            (define c #f #;(⟪α⟫->s γ))
            (define Mut (-W¹ mut mut))
            (for*/union : (℘ -ς) ([C (σ@ σ γ)] [Vₛ* (σ@ σ α)])
                        (define W-c (-W¹ C c))
                        (define Wₛ* (-W¹ Vₛ* sₛ))
                        (mon l³* $ (ℒ-with-mon ℒ ℓᵢ) W-c Wᵥ Γ ⟪ℋ⟫ Σ
                             (ap∷ (list Wₛ* Mut) '() ⊥ρ ℒ ⟦k⟧)))]
           [(-● _)
            (define ⟦ok⟧
              (let ([⟦hv⟧ (mk-app (ℒ-with-l ℒ 'havoc)
                                      (mk-rt (-W¹ -●.V #f))
                                      (list (mk-rt Wᵥ)))])
                (mk-app (ℒ-with-l ℒ 'havoc) (mk-rt (-W¹ 'void 'void)) (list ⟦hv⟧))))
            (define ⟦er⟧ (mk-rt (blm)))
            (app $ ℒ (-W¹ p p) (list Wₛ) Γ ⟪ℋ⟫ Σ (if∷ l ⟦ok⟧ ⟦er⟧ ⊥ρ ⟦k⟧))]
           [_ (⟦k⟧ (blm) $ Γ ⟪ℋ⟫ Σ)])]
        [_
         (define blm (blm-arity (-ℒ-app ℒ) (show-o mut) 2 (map -W¹-V Ws)))
         (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ)]))
    ⟦mut⟧)

  (: app-apply : -⟦f⟧)
  (define (app-apply $ ℒ Ws Γ ⟪ℋ⟫ Σ ⟦k⟧)
    (match-define (-Σ σ _ M) Σ)
    (define-values (ℓ l) (unpack-ℒ ℒ))

    (: blm-for : -V (Listof -V) → -Γ → (℘ -ς))
    (define ((blm-for C Vs) Γ)
      (define blm (-blm l 'apply (list C) Vs ℓ))
      (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ))

    (: do-apply : -W¹ (Listof -W¹) -W¹ → -Γ → (℘ -ς))
    (define ((do-apply W-func W-inits W-rest) Γ)
      (define num-inits (length W-inits))
      (match-define (-W¹ V-func t-func) W-func)

      (define (blm-arity [msg : -V]) : (℘ -ς)
        (define blm-args (append (map -W¹-V W-inits) (list (-W¹-V W-rest))))
        (define blm (-blm l 'apply (list msg) blm-args ℓ))
        (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ))
      
      (cond
        [(-●? V-func)
         ((app-opq t-func) $ ℒ (append W-inits (list W-rest)) Γ ⟪ℋ⟫ Σ ⟦k⟧)]
        [else
         (define num-inits (length W-inits))
         (match (V-arity V-func)
           [(? index? fixed-arity)
            (define num-remaining-args (- fixed-arity num-inits))
            (cond
              ;; Fewer init arguments than required. Check rest-arg list
              [(>= num-remaining-args 0)
               (define possible-args (unalloc (-Σ-σ Σ) W-rest num-remaining-args))
               (for/union : (℘ -ς) ([?remaining-args (in-set possible-args)])
                 (match ?remaining-args
                   [(cons W-remainings (-W¹ (-b (list)) _))
                    (app $ ℒ W-func (append W-inits W-remainings) Γ ⟪ℋ⟫ Σ ⟦k⟧)]
                   [_
                    (blm-arity (format-symbol "~a argument(s)" fixed-arity))]))]
              ;; More init arguments than required
              [else
               (blm-arity (format-symbol "~a argument(s)" fixed-arity))])]
           [(arity-at-least arity.min)
            (define remaining-inits (- arity.min num-inits))
            (cond
              ;; arg-init maybe too short, then retrieve some more
              [(>= remaining-inits 0)
               (define possible-rests (unalloc (-Σ-σ Σ) W-rest remaining-inits))
               (for/union : (℘ -ς) ([?remaining (in-set possible-rests)])
                 (match ?remaining
                   [(cons W-inits* W-rest*)
                    (app/rest $ ℒ W-func (append W-inits W-inits*) W-rest* Γ ⟪ℋ⟫ Σ ⟦k⟧)]
                   [_
                    (blm-arity (format-symbol "~a+ arguments(s)" arity.min))]))]
              ;; arg-init long than min-arity, then allocate some
              [else
               (define num-allocs (- remaining-inits))
               (define-values (W-inits* W-rest₁) (split-at W-inits arity.min))
               (define V-rest (alloc-rest-args! Σ Γ ⟪ℋ⟫ ℒ W-rest₁ #:end (-W¹-V W-rest)))
               (app/rest $ ℒ W-func W-inits* (-W¹ V-rest #f) Γ ⟪ℋ⟫ Σ ⟦k⟧)])]
           [a
            (error 'do-apply "handle arity ~a" a)])]))

    (match Ws
      [(list Wₕ W-inits ... W-rest)
       (with-MΓ+/-oW (M σ Γ 'procdedure? Wₕ)
         #:on-t (do-apply Wₕ (cast W-inits (Listof -W¹)) W-rest)
         #:on-f (blm-for 'procedure? (list (-W¹-V Wₕ))))]
      [_
       (define-values (ℓ l) (unpack-ℒ ℒ))
       (define blm (blm-arity ℓ l (arity-at-least 2) (map -W¹-V Ws)))
       (⟦k⟧ blm $ Γ ⟪ℋ⟫ Σ)]))

  ;; FIXME tmp hack for `make-sequence` use internallyr
  (: app-make-sequence : -⟦f⟧)
  (define (app-make-sequence $ ℒ Ws Γ ⟪ℋ⟫ Σ ⟦k⟧)
    (define Vs (list -car -cdr 'values -one -cons? -ff -ff))
    (define t (-t.@ 'values (list -car -cdr 'values -one -cons? -ff -ff)))
    (define A (-W Vs t))
    (⟦k⟧ A $ Γ ⟪ℋ⟫ Σ))

  (define (app-opq [sₕ : -?t]) : -⟦f⟧
    (λ ($ ℒ Ws Γ ⟪ℋ⟫ Σ ⟦k⟧)
      (define sₐ #f #|TODO make sure ok|# #;(apply ?t@ sₕ (map -W¹-t Ws)))
      (for ([W (in-list Ws)])
        (add-leak! Σ (-W¹-V W)))
      (define αₖ (-ℋ𝒱))
      (define κ (-κ (bgn0.e∷ (-W -●.Vs sₐ) '() ⊥ρ ⟦k⟧) Γ ⟪ℋ⟫ '()))
      (σₖ⊕! Σ αₖ κ)
      {set (-ς↑ αₖ ⊤Γ ⟪ℋ⟫∅)}))

  (: app/rest : -$ -ℒ -W¹ (Listof -W¹) -W¹ -Γ -⟪ℋ⟫ -Σ -⟦k⟧ → (℘ -ς))
  (define (app/rest $ ℒ W-func W-inits W-rest Γ ⟪ℋ⟫ Σ ⟦k⟧)
    (match-define (-W¹ V-func t-func) W-func)
    (match V-func
      [(-Clo xs ⟦e⟧ _ _)
       (error 'app/rest "TODO: lambda")]
      [(-Case-Clo clauses _ _)
       (error 'app/rest "TODO: case-lambda")]
      [(-Ar C α l³)
       (error 'app/rest "TODO: guarded function")]
      [(? -o? o)
       (for/union : (℘ -ς) ([V-list (in-set (unalloc-approximate-prefix (-Σ-σ Σ) (-W¹-V W-rest)))])
         (define W-inits* : (Listof -W¹)
           (for/list ([V (in-list V-list)])
             (-W¹ V #f)))
         (app $ ℒ W-func (append W-inits W-inits*) Γ ⟪ℋ⟫ Σ ⟦k⟧))]
      [_
       (error 'app/rest "unhandled: ~a" (show-W¹ W-func))]))

  (: alloc-init-args! : -Σ -Γ -ρ -⟪ℋ⟫ -?t (Listof Symbol) (Listof -W¹) → -ρ)
  (define (alloc-init-args! Σ Γₑᵣ ρₑₑ ⟪ℋ⟫ sₕ xs Ws)
    
    (define φsₕ
      (let* ([bnd (list->seteq xs)]
             [fvs (set-subtract (if (or (-λ? sₕ) (-case-λ? sₕ)) (fvₜ sₕ) ∅eq) bnd)])
        (for*/set: : (℘ -t) ([φ (in-set (-Γ-facts Γₑᵣ))]
                             [fv⟦φ⟧ (in-value (fvₜ φ))]
                             #:unless (set-empty? fv⟦φ⟧)
                             #:when (⊆ fv⟦φ⟧ fvs))
          φ)))
    (define ρ₀ (ρ+ ρₑₑ -x-dummy (-α->⟪α⟫ (-α.fv ⟪ℋ⟫ φsₕ))))
    (for/fold ([ρ : -ρ ρ₀]) ([x xs] [Wₓ Ws])
      (match-define (-W¹ Vₓ sₓ) Wₓ)
      (define α (-α->⟪α⟫ (-α.x x ⟪ℋ⟫ (predicates-of-W (-Σ-σ Σ) Γₑᵣ Wₓ))))
      (σ⊕! Σ Γₑᵣ α Wₓ)
      (ρ+ ρ x α)))

  (: alloc-rest-args! ([-Σ -Γ -⟪ℋ⟫ -ℒ (Listof -W¹)] [#:end -V] . ->* . -V))
  (define (alloc-rest-args! Σ Γ ⟪ℋ⟫ ℒ Ws #:end [Vₙ -null])

    (: precise-alloc! ([(Listof -W¹)] [Natural] . ->* . -V))
    ;; Allocate vararg list precisely, preserving length
    (define (precise-alloc! Ws [i 0])
      (match Ws
        [(list) Vₙ]
        [(cons Wₕ Ws*)
         (define αₕ (-α->⟪α⟫ (-α.var-car ℒ ⟪ℋ⟫ i)))
         (define αₜ (-α->⟪α⟫ (-α.var-cdr ℒ ⟪ℋ⟫ i)))
         (σ⊕! Σ Γ αₕ Wₕ)
         (σ⊕V! Σ αₜ (precise-alloc! Ws* (+ 1 i)))
         (-Cons αₕ αₜ)]))
    
    ;; Allocate length up to 2 precisely to let `splay` to go through
    ;; This is because `match-lambda*` expands to varargs with specific
    ;; expectation of arities
    (match Ws
      [(or (list) (list _) (list _ _) (list _ _ _))
       (precise-alloc! Ws)]
      [(? pair?)
       (define αₕ (-α->⟪α⟫ (-α.var-car ℒ ⟪ℋ⟫ #f)))
       (define αₜ (-α->⟪α⟫ (-α.var-cdr ℒ ⟪ℋ⟫ #f)))
       (define Vₜ (-Cons αₕ αₜ))
       ;; Allocate spine for var-arg lists
       (σ⊕V! Σ αₜ Vₜ)
       (σ⊕V! Σ αₜ Vₙ)
       ;; Allocate elements in var-arg lists
       (for ([W Ws])
         (σ⊕! Σ Γ αₕ W))
       Vₜ]))

  ;; FIXME Duplicate macros
  (define-simple-macro (with-MΓ+/-oW (M:expr σ:expr Γ:expr o:expr W:expr ...) #:on-t on-t:expr #:on-f on-f:expr)
    (MΓ+/-oW/handler on-t on-f M σ Γ o W ...))

  (: unalloc : -σ -W¹ Natural → (℘ (Option (Pairof (Listof -W¹) -W¹))))
  ;; Convert a list in the object language into one in the meta language
  ;; of given lengths
  (define (unalloc σ W num-inits)
    (match-define (-W¹ V _) W)
    (let go ([V : -V V] [num-inits : Natural num-inits])
      (error 'unalloc "TODO")))

  (: unalloc-approximate-prefix : -σ -V → (℘ (Listof -V)))
  (define (unalloc-approximate-prefix σ V)
    (define-set seen : ⟪α⟫ #:eq? #t #:as-mutable-hash? #t)
    (define Tail : (℘ (Listof -V)) {set '()})
    (let go ([V : -V V])
      (match V
        [(-Cons αₕ αₜ)
         (cond
           [(seen-has? αₜ) Tail]
           [else
            (seen-add! αₜ)
            (define Vₕs (σ@ σ αₕ))
            (for/union : (℘ (Listof -V)) ([Vₜ (in-set (σ@ σ αₜ))] [Vₕ (in-set Vₕs)])
              (define V-lists (go Vₜ))
              (for/set: : (℘ (Listof -V)) ([V-list (in-set V-lists)])
                (cons Vₕ V-list)))])]
        [_ Tail])))
  )