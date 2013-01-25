#lang racket

;; Json-mapping, Copyright (C) 2013 Adolfo Pérez Álvarez
;;
;; This library is free software; you can redistribute it and/or modify it under
;; the terms of the GNU Lesser General Public License as published by the Free
;; Software Foundation; either version 2.1 of the License, or (at your option)
;; any later version.
;;
;; This library is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
;; details.
;;
;; You should have received a copy of the GNU Lesser General Public License
;; along with this library; if not, write to the Free Software Foundation, Inc.,
;; 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA 

;; TODO:
;;  - Use distinct exceptions for datum->jsexpr and jsexpr->datum (right now,
;;    both use a generic exn:fail:json exception).
;;  - Proper error checking (arity of constructor functions, ensure structs are
;;    transparent, etc.)
;;  - Explicit support for `null' (workaround: (literal (json-null)))
;;  - More exhaustive test cases.
;;  - Documentation.

(require (for-syntax (only-in unstable/sequence in-syntax)))
(require (for-syntax racket/syntax))

(require racket/format)

(struct exn:fail:json exn:fail ())

(define (raise-json-error expected value)
  (raise (exn:fail:json
          (~a "Cannot map jsexpr to Racket datum; "
              "expected: " expected "; "
              "found: " value)
          (current-continuation-marks))))

(struct json-mapper (datum->jsexpr jsexpr->datum))

(define (datum->jsexpr mapper datum)
  ((json-mapper-datum->jsexpr mapper) datum))

(define (jsexpr->datum mapper jsexpr)
  ((json-mapper-jsexpr->datum mapper) jsexpr))

(define-syntax (json-mapping stx)
  (syntax-case stx ()
    [(_ spec)
     (with-syntax* ([js->datum-id
                     (generate-temporary)]
                    [js->datum-body
                     (emit-jsexpr->datum-body #'(js->datum-id spec))]
                    [datum->js-id
                     (generate-temporary)]
                    [datum->js-body
                     (emit-datum->jsexpr-body #'(datum->js-id spec))])
       #'(json-mapper (λ (datum->js-id) datum->js-body)
                      (λ (js->datum-id) js->datum-body)))]))

(begin-for-syntax
  (define-syntax-rule (for/syntax stx vars body)
    (datum->syntax stx (for/list vars body)))
  
  (define (emit-primitive-body p-expr? type id)
    #`(if #,p-expr? #,id (raise-json-error '#,type #,id)))
  
  (define (emit-list-body stx emitter)
    (syntax-case stx (or)
      [(id (list mapping))
       (with-syntax* ([x (generate-temporary)]
                      [body (emitter #'(x mapping))])
         #'(if (list? id)
               (for/list ([x (in-list id)])
                 body)
               (raise-json-error '(list mapping) id)))]))
  
  (define (emit-or-body stx emitter)
    (syntax-case stx (or)
      [(id (or))
       #'(raise-json-error '(or) id)]
      [(id (or mapping))
       (emitter #'(id mapping))]
      [(id (or mapping rest ...))
       (with-syntax ([body (emitter #'(id mapping))]
                     [rest-body (emitter #'(id (or rest ...)))])
         #'(with-handlers ([exn:fail:json?
                            (λ (_) rest-body)])
             body))]))
  (define (emit-hash-body stx emitter)
    (syntax-case stx (: object)
      [(id (object [name : mapping] ...))
       (with-syntax* ([(tmp ...)
                       (generate-temporaries #'(name ...))]
                      [(value ...)
                       (for/syntax #'here ([n (in-syntax #'(name ...))])
                         #`(hash-ref id '#,n))]
                      [(expr/tmp ...)
                       (for/syntax #'here ([t (in-syntax #'(tmp ...))]
                                           [m (in-syntax #'(mapping ...))])
                         (emitter #`(#,t #,m)))])
         #'(if (hash? id)
               (let ([tmp value]
                     ...)
                 (make-immutable-hash `((name . ,expr/tmp) ...)))
               (raise-json-error '(object [name : mapping] ...) id)))]))
  
  (define (emit-datum->jsexpr-body stx)
    (syntax-case stx (: or bool number string literal list object)
      [(id number)
       (emit-primitive-body #'(number? id) #'number #'id)]
      [(id bool)
       (emit-primitive-body #'(boolean? id) #'bool #'id)]
      [(id string)
       (emit-primitive-body #'(string? id) #'string #'id)]
      [(id (literal datum))
       (emit-primitive-body #'(equal? id datum) #'(literal datum) #'id)]
      [(id (list mapping))
       (emit-list-body #'(id (list mapping)) emit-datum->jsexpr-body)]
      [(id (or mapping ...))
       (emit-or-body #'(id (or mapping ...)) emit-datum->jsexpr-body)]
      [(id (object [name : mapping] ...))
       (emit-hash-body #'(id (object [name : mapping] ...)) emit-datum->jsexpr-body)]
      [(id (object mk [name : mapping] ...))
       (with-syntax* ([(tmp ...)
                       (generate-temporaries #'(name ...))]
                      [vec 
                       (generate-temporary)]
                      [(field-value ...)
                       (for/syntax #'here ([_ (in-syntax #'(name ...))]
                                           [i (in-naturals 1)])
                         #`(vector-ref vec #,i))]
                      [(value ...)
                       (for/syntax #'here ([t (in-syntax #'(tmp ...))]
                                           [m (in-syntax #'(mapping ...))])
                         (emit-datum->jsexpr-body #`(#,t #,m)))])
         #'(if (struct? id)
               (let* ([vec (struct->vector id)]
                      [tmp field-value]
                      ...)
                 (make-immutable-hash `((name . ,value) ...)))
               (raise-json-error '(object mk [name : mapping] ...) id)))]
      [(id expr)
       #'(datum->jsexpr expr id)]))
  
  (define (emit-jsexpr->datum-body stx)
    (syntax-case stx (: or bool number string literal list object)
      [(id number)
       (emit-primitive-body #'(number? id) #'number #'id)]
      [(id bool)
       (emit-primitive-body #'(boolean? id) #'bool #'id)]
      [(id string)
       (emit-primitive-body #'(string? id) #'string #'id)]
      [(id (literal datum))
       (emit-primitive-body #'(equal? id datum) #'(literal datum) #'id)]
      [(id (list mapping))
       (emit-list-body #'(id (list mapping)) emit-jsexpr->datum-body)]
      [(id (or mapping ...))
       (emit-or-body #'(id (or mapping ...)) emit-jsexpr->datum-body)]
      [(id (object [name : mapping] ...))
       (emit-hash-body #'(id (object [name : mapping] ...)) emit-datum->jsexpr-body)]
      [(id (object mk [name : mapping] ...))
       (with-syntax* ([(tmp ...)
                       (generate-temporaries #'(name ...))]
                      [(body ...)
                       (for/syntax #'here ([t (in-syntax #'(tmp ...))]
                                           [m (in-syntax #'(mapping ...))])
                         (emit-jsexpr->datum-body #`(#,t #,m)))])
         #'(if (hash? id)
               (let ([tmp (hash-ref id 'name)]
                     ...)
                 (mk body ...))
               (raise-json-error '(object mk [name : mapping] ...) id)))]
      [(id expr)
       #'(jsexpr->datum expr id)])))

(provide json-mapping
         datum->jsexpr
	 jsexpr->datum)

(module+ test
  (require rackunit)
  
  (define a-bool
    (json-mapping bool))

  (define a-number
    (json-mapping number))
  
  (define a-string
    (json-mapping string))

  (define a-literal
    (json-mapping (literal "a")))

  (define a-list
    (json-mapping (list number)))
  
  (for [(datum `((,a-bool #t #f)
                 (,a-number 1 1.2)
                 (,a-string "a")
                 (,a-list () (1 2))))]
    (match datum
      [`(,m ,ds ...)
       (for [(d ds)]
         ;; For every mapper on booleans, numbers, strings
         ;; or lists, all mapping functions are the identity
         ;; function.
         (check-equal? (datum->jsexpr m d) d)
         (check-equal? (jsexpr->datum m d)
                       (datum->jsexpr m d)))]))
  
  (for [(f `(,jsexpr->datum ,datum->jsexpr))]
    (check-exn exn:fail:json? (thunk (f a-bool 'a)))
    (check-exn exn:fail:json? (thunk (f a-number 'a)))
    (check-exn exn:fail:json? (thunk (f a-string 'a)))
    (check-exn exn:fail:json? (thunk (f a-literal "b")))
    (check-exn exn:fail:json? (thunk (f a-list '(a)))))
  
  (check-equal? (datum->jsexpr (json-mapping (object [foo : string]))
                               (hash 'foo "a"))
                (hash 'foo "a"))
  (check-equal? (jsexpr->datum (json-mapping (object [foo : string]))
                               (hash 'foo "a"))
                (hash 'foo "a"))
  
  (struct foo (a b c) #:transparent)
  
  (define an-object
    (json-mapping
     (object foo
             [a : number]
             [b : string]
             [c : (list number)])))
  
  (check-true (foo? (jsexpr->datum an-object
                                   (hash 'a 1
                                         'b "2"
                                         'c '(3)))))
  (check-equal? (datum->jsexpr an-object (foo 1 "a" '()))
                (hash 'a 1 'b "a" 'c '()))
  
  (struct bar (foo) #:transparent)
  
  (define a-nested-object
    (json-mapping
     (object bar
             [foo : an-object])))
  
  (check-true (bar? (jsexpr->datum
                     a-nested-object
                     (hash 'foo
                           (hash 'a 1
                                 'b "2"
                                 'c '(3))))))
  
  (check-equal? (datum->jsexpr
                 a-nested-object
                 (bar (foo 1 "2" '(3))))
                (hash 'foo (hash 'a 1 'b "2" 'c '(3))))
  
  (define or-mapping
    (json-mapping (or number an-object)))
  
  (check-equal? (jsexpr->datum or-mapping 1) 1)
  (check-true (foo? (jsexpr->datum or-mapping (hash 'a 1 'b "a" 'c '(1 2 3)))))
  (check-exn exn:fail:json? (thunk (jsexpr->datum or-mapping "a")))
  
  (check-equal? (datum->jsexpr or-mapping 1) 1)
  (check-equal? (datum->jsexpr or-mapping (foo 1 "a" '(1 2 3)))
                (hash 'a 1 'b "a" 'c '(1 2 3)))
  (check-exn exn:fail:json? (thunk (datum->jsexpr or-mapping "a"))))
