#lang racket/base
(require racket/contract/base
         racket/contract/combinator
         racket/sequence)

(define path-piece?
  (or/c path-string? (symbols 'up 'same)))

(define port-number? (between/c 1 65535))
(define tcp-listen-port? (between/c 0 65535))

(define (non-empty-string? x)
  (and (string? x) (not (zero? (string-length x)))))

;; ryanc added:

;; (if/c predicate then/c else/c) applies then/c to satisfying
;;   predicate, else/c to those that don't.
(define (if/c predicate then/c else/c)
  #|
  Naive version:
    (or/c (and/c predicate then/c)
          (and/c (not/c predicate) else/c))
  But that applies predicate twice.
  |#
  (let ([then-ctc (coerce-contract 'if/c then/c)]
        [else-ctc (coerce-contract 'if/c else/c)])
    (define name (build-compound-type-name 'if/c predicate then-ctc else-ctc))
    ;; Special case: if both flat contracts, make a flat contract.
    (if (and (flat-contract? then-ctc)
             (flat-contract? else-ctc))
        ;; flat contract
        (let ([then-pred (flat-contract-predicate then-ctc)]
              [else-pred (flat-contract-predicate else-ctc)])
          (define (pred x)
            (if (predicate x) (then-pred x) (else-pred x)))
          (flat-named-contract name pred))
        ;; ho contract
        (let ([then-proj (contract-projection then-ctc)]
              [then-fo (contract-first-order then-ctc)]
              [else-proj (contract-projection else-ctc)]
              [else-fo (contract-first-order else-ctc)])
          (define ((proj blame) x)
            (if (predicate x)
                ((then-proj blame) x)
                ((else-proj blame) x)))
          (make-contract
           #:name name
           #:projection proj
           #:first-order
           (lambda (x) (if (predicate x) (then-fo x) (else-fo x))))))))

;; failure-result/c : contract
;; Describes the optional failure argument passed to hash-ref, for example.
;; If the argument is a procedure, it must be a thunk, and it is applied. Otherwise
;; the argument is simply the value to return.
(define failure-result/c
  (if/c procedure? (-> any) any/c))

;; rename-contract : contract any/c -> contract
;; If the argument is a flat contract, so is the result.
(define (rename-contract ctc name)
  (let ([ctc (coerce-contract 'rename-contract ctc)])
    (if (flat-contract? ctc)
        (flat-named-contract name (flat-contract-predicate ctc))
        (let* ([ctc-fo (contract-first-order ctc)]
               [proj (contract-projection ctc)])
          (make-contract #:name name
                           #:projection proj
                           #:first-order ctc-fo)))))

;; Added by asumu
;; option/c : contract -> contract
(define (option/c ctc-arg)
  (define ctc (coerce-contract 'option/c ctc-arg))
  (cond [(flat-contract? ctc) (flat-option/c ctc)]
        [(chaperone-contract? ctc) (chaperone-option/c ctc)]
        [else (impersonator-option/c ctc)]))

(define (option/c-name ctc)
  (build-compound-type-name 'option/c (base-option/c-ctc ctc)))

(define (option/c-projection ctc)
  (define ho-proj (contract-projection (base-option/c-ctc ctc)))
  (λ (blame)
    (define partial (ho-proj blame))
    (λ (val)
      (if (not val) val (partial val)))))

(define ((option/c-first-order ctc) v)
  (or (not v) (contract-first-order-passes? (base-option/c-ctc ctc) v)))

(define (option/c-stronger? this that)
  (and (base-option/c? that)
       (contract-stronger? (base-option/c-ctc this)
                           (base-option/c-ctc that))))

(struct base-option/c (ctc))

(struct flat-option/c base-option/c ()
        #:property prop:flat-contract
        (build-flat-contract-property
          #:name option/c-name
          #:first-order option/c-first-order
          #:stronger option/c-stronger?))

(struct chaperone-option/c base-option/c ()
        #:property prop:chaperone-contract
        (build-chaperone-contract-property
          #:name option/c-name
          #:first-order option/c-first-order
          #:projection option/c-projection
          #:stronger option/c-stronger?))

(struct impersonator-option/c base-option/c ()
        #:property prop:contract
        (build-contract-property
          #:name option/c-name
          #:first-order option/c-first-order
          #:projection option/c-projection
          #:stronger option/c-stronger?))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Flat Contracts
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define truth/c
  (flat-named-contract '|truth value| (lambda (x) #t)))

;; Added by ntoronto

(define (treeof elem-contract)
  (or/c elem-contract
        (listof (recursive-contract (treeof elem-contract) #:flat))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Exports
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide/contract
 [path-piece? contract?]
 [port-number? contract?]
 [tcp-listen-port? contract?]

 [non-empty-string? predicate/c]

 [if/c (-> procedure? contract? contract? contract?)]
 [failure-result/c contract?]
 [rename-contract (-> contract? any/c contract?)]
 [rename option/c maybe/c (-> contract? contract?)]

 [truth/c flat-contract?]
 
 [treeof (contract? . -> . contract?)])
(provide sequence/c)
