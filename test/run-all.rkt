#lang racket
(require "../machine.rkt")

(define verbose? #f)

(for ([filename
       ; commandline parameters as files to run. Run all by default.
       (match (current-command-line-arguments)
         [(vector) (sort (map path->string (directory-list)) string<=?)]
         [names names])]
      #:when (regexp-match? #rx"sch$" filename))
  (let ([lines (with-input-from-file filename
                 (thunk (length (port->lines (current-input-port)))))]
        [name (string-trim filename ".sch")])
    (with-input-from-file filename
      (thunk
       (let ([prog (for/list ([form (in-port read)]) form)])
         (if verbose?
             (begin
               (printf "~a: ~a lines~n" name lines)
               (for ([a (time (ev prog))]) (printf "-- ~a~n" a))
               (printf "~n"))
             (let-values ([(_r time _1 _2) (time-apply ev (list prog))])
               (printf "~a & ~a & ~a \\\\ ~n" name lines time))))))))