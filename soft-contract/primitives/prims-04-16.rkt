#lang typed/racket/base

(require racket/match
         racket/contract
         racket/bool
         racket/string
         racket/math
         racket/list
         racket/stream
         racket/dict
         racket/function
         racket/set
         racket/flonum
         racket/fixnum
         racket/generator
         racket/random
         racket/format
         racket/splicing
         typed/racket/unit
         syntax/parse/define
         set-extras
         "../utils/debug.rkt"
         (except-in "../ast/signatures.rkt" normalize-arity arity-includes?)
         "../runtime/signatures.rkt"
         "../signatures.rkt"
         "signatures.rkt"
         "def.rkt"
         (for-syntax racket/base
                     racket/syntax
                     syntax/parse))

(provide prims-04-16@)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; 4.16 Sets
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-unit prims-04-16@
  (import prim-runtime^ widening^ pc^)
  (export)

  ;;;;; Hash Sets
  (def-preds (set-equal? set-eqv? set-eq? set? set-mutable? set-weak?))
  (def set (∀/c (α) (() #:rest (listof α) . ->* . (and/c immutable? (set/c α)))))
  (def seteqv (∀/c (α) (() #:rest list? . ->* . (and/c generic-set? set-eqv? (set/c α)))))
  (def seteq (∀/c (α) (() #:rest list? . ->* . (and/c generic-set? set-eq? (set/c α)))))
  (def mutable-set (∀/c (α) (() #:rest list? . ->* . (and/c generic-set? set-equal? set-mutable? (set/c α)))))
  (def mutable-seteqv (∀/c (α) (() #:rest list? . ->* . (and/c generic-set? set-eqv? set-mutable? (set/c α)))))
  (def mutable-seteq (∀/c (α) (() #:rest list? . ->* . (and/c generic-set? set-eq? set-mutable? (set/c α)))))
  (def weak-set (∀/c (α) (() #:rest list? . ->* . (and/c generic-set? set-equal? set-weak? (set/c α)))))
  (def weak-seteqv (∀/c (α) (() #:rest list? . ->* . (and/c generic-set? set-eqv? set-weak? (set/c α)))))
  (def weak-seteq (∀/c (α) (() #:rest list? . ->* . (and/c generic-set? set-eq? set-weak? (set/c α)))))
  (def list->set (∀/c (α) ((listof α) . -> . (and/c generic-set? set-equal? (set/c α)))))
  (def list->seteqv (∀/c (α) ((listof α) . -> . (and/c generic-set? set-eqv? (set/c α)))))
  (def list->seteq (∀/c (α) ((listof α) . -> . (and/c generic-set? set-eq? (set/c α)))))
  (def list->mutable-set (∀/c (α) ((listof α) . -> . (and/c generic-set? set-equal? set-mutable? (set/c α)))))
  (def list->mutable-seteqv (∀/c (α) (list? . -> . (and/c generic-set? set-eqv? set-mutable? (set/c α)))))
  (def list->mutable-seteq (∀/c (α) ((listof α) . -> . (and/c generic-set? set-eq? set-mutable? (set/c α)))))
  (def list->weak-set (∀/c (α) ((listof α) . -> . (and/c generic-set? set-equal? set-weak? (set/c α)))))
  (def list->weak-seteqv (∀/c (α) ((listof α) . -> . (and/c generic-set? set-eqv? set-weak? (set/c α)))))
  (def list->weak-seteq (∀/c (α) ((listof α) . -> . (and/c generic-set? set-eq? set-weak? (set/c α)))))

;;;;; 4.16.2 Set Predicates and Contracts
  (def-pred generic-set?)
  #;[set-implements ; FIXME listof
     ((generic-set?) #:rest (listof symbol?) . ->* . boolean?)]
  #;[set-implements/c ; FIXME varargs, contract?
     (symbol? . -> . flat-contract?)]
  (def (set/c ℓ Ws $ Γ ⟪ℋ⟫ Σ ⟦k⟧)
    #:init ([W contract? #|TODO chaperone-contract?|#])
    (match-define (-W¹ _ t) W)
    (define α (-α->⟪α⟫ (-α.set/c-elem ℓ ⟪ℋ⟫)))
    (σ⊕! Σ Γ α W)
    (define C (-Set/C (-⟪α⟫ℓ α (ℓ-with-id ℓ 'set/c))))
    (⟦k⟧ (-W (list C) (?t@ 'set/c t)) $ Γ ⟪ℋ⟫ Σ))

;;;;; 4.16.3 Generic Set Interface

  ;; 4.16.3.1 Set Methods
  (def-pred set-member? (generic-set? any/c))
  (def set-add (∀/c (α) ((and/c immutable? (set/c α)) α . -> . (set/c α))))
  (def set-remove (∀/c (α _) ((and/c immutable? (set/c α)) _ . -> . (set/c α))))
  (def* (set-add! set-remove!) ; FIXME no!
    (∀/c (_) ((and/c generic-set? set-mutable?) _ . -> . void?)))
  (def-pred set-empty? {generic-set?})
  (def set-count (generic-set? . -> . exact-nonnegative-integer?))
  (def set-first (∀/c (α) ((set/c α) . -> . α)))
  (def set-rest (∀/c (α) ((set/c α) . -> . (set/c α))))
  (def set->stream (generic-set? . -> . stream?))
  (def set-copy (generic-set? . -> . generic-set?))
  (def set-copy-clear (generic-set? . -> . (and/c generic-set? set-empty?)))
  (def set-clear
    ((and/c generic-set? (not/c set-mutable?)) . -> . (and/c generic-set? set-empty?)))
  (def set-clear!
    ((and/c generic-set? set-mutable?) . -> . void?))
  ;; FIXME listof

  (def set-union
    ; FIXME enforce sets of the same type
    ; FIXME uses
    #;((generic-set?) #:rest (listof generic-set?) . ->* . generic-set?)
    (∀/c (α) ((set/c α) (set/c α) . -> . (set/c α))))
  #|
  (def set-union! ; FIXME enforce sets of the same type
  ((generic-set?) #:rest (listof generic-set?) . ->* . void?))
  (def set-intersect
  ((generic-set?) #:rest (listof generic-set?) . ->* . generic-set?))
  (def set-intersect!
  ((generic-set?) #:rest (listof generic-set?) . ->* . void?))
  (def set-subtract
  ((generic-set?) #:rest (listof generic-set?) . ->* . generic-set?))
  (def set-subtract!
  ((generic-set?) #:rest (listof generic-set?) . ->* . void?))
  (def set-symmetric-difference
  ((generic-set?) #:rest (listof generic-set?) . ->* . generic-set?))
  (def set-symmetric-difference!
  ((generic-set?) #:rest (listof generic-set?) . ->* . void?))|#
  (def* (set=? subset? proper-subset?) ; FIXME enforce same `set` type
    (generic-set? generic-set? . -> . boolean?))
  (def set->list (∀/c (α) ((set/c α) . -> . (listof α))))
  (def set-map (∀/c (α β) ((set/c α) (α . -> . β) . -> . (listof β)))) ; FIXME varargs
  (def set-for-each (∀/c (α) ((set/c α) (α . -> . any) . -> . void?)))
  (def in-set (generic-set? . -> . sequence?))

;;;;; 4.16.4 Custom Hash Sets
  #;[make-custom-set-types ; FIXME uses
     ((or/c (any/c any/c . -> . any/c)
            (any/c any/c (any/c any/c . -> . any/c) . -> . any/c))
      . -> .
      (values (any/c . -> . boolean?)
              (any/c . -> . boolean?)
              (any/c . -> . boolean?)
              (any/c . -> . boolean?)
              ([] [stream?] . ->* . generic-set?)
              ([] [stream?] . ->* . generic-set?)
              ([] [stream?] . ->* . generic-set?)))]
  )
