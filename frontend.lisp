(in-package :genlin)
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
;; A pretty front-end
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

(defparameter *tweakables*
  '(*menu*
    *debug*
    *stat-interval*
    *parallel*
    *dataset*
    *data-path*
    *training-ratio*
    *method-key*
    *number-of-islands*
    *population-size*
    *mutation-rate*
    *migration-rate*
    *migration-size*
    *greedy-migration*
    *track-genealogy*
    *min-len*
    *max-len*
    *max-start-len*
    *opcode-bits*
    *source-register-bits*
    *destination-register-bits*
    *rounds*
    *target*))    

(defun print-tweakables ()
  (loop
     for symbol in *tweakables*
     for i from 0 to (length *tweakables*) do
       (format t "[~d] ~A: ~S~%     ~A~%" i (symbol-name symbol) (symbol-value symbol)
               (documentation symbol 'variable))))

(defun print-operations ()
  (let ((used #\*)
        (unused #\space))
    (loop
       for op in (coerce *operations* 'list)
       for i from 0 to (length *operations*) do
         (format t "~A ~A~%"
                 (func->string op)
                 (if (< i (expt 2 *opcode-bits*)) used unused)))))

(defun string->earmuff (string)
  (let ((muffed (concatenate 'string "*" (string-upcase string) "*")))
    (intern muffed)))

(defun earmuff->string (symbol)
  (let ((string (remove #\* (symbol-name symbol))))
    string))

(defun get-opt-arg (list key)
  (let ((anything-there (member key list :test #'equalp)))
    (when anything-there
      (cadr anything-there))))

(defun parse-command-line-args ()
  (let ((args (cdr sb-ext:*posix-argv*)))
;;    (FORMAT T "ARGV = ~S~%" args)
    (loop for param in *tweakables* do
         (let ((key (concatenate 'string "--"
                                 (string-downcase (earmuff->string param)))))

           (when (member key args :test #'equalp)
;;             (FORMAT T "FOUND OPT: ~S = ~S~%" key (get-opt-arg args key))
             (setf (symbol-value param)
                   (read-from-string (get-opt-arg args key)))
             (format t "Setting ~A to ~A...~%"
                     param (symbol-value param)))))))
;;           (format t "~S = ~S~%" param (symbol-value param))))))

(defun menu ()
  "The front end and user interface of the programme. Allows the user
to tweak a number of dynamically scoped, special variables, and then
launch setup and evolve."
  (flet ((validate (n)      
           (or (eq n :Q) 
               (and (numberp n)
                    (<= 0 n)
                    (< n (length *tweakables*))))))    
    (let ((sel)
          (target)
          (rounds)
          (method))
      (loop do
           (hrule)
           (print-tweakables)
           (hrule)
           (loop do 
                (format t "~%ENTER NUMBER OF PARAMETER TO TWEAK, OR :Q TO PROCEED.~%")
                (princ "~ ")
;                (clear-input)
                (setf sel (read))
                (when (validate sel) (return)))
           (when (eq sel :Q) (return))
           (format t "~%YOU SELECTED ~D: ~A~%CURRENT VALUE: ~S~%     ~A~%~%"
                   sel
                   (elt *tweakables* sel)
                   (symbol-value (elt *tweakables* sel))
                   (documentation (elt *tweakables* sel) 'variable))
           (format t "ENTER NEW VALUE (BE CAREFUL, AND MIND THE SYNTAX)~%~~ ")
           (setf (symbol-value (elt *tweakables* sel)) (read))
           (format t "~A IS NOW SET TO ~A~%"
                   (elt *tweakables* sel)
                   (symbol-value (elt *tweakables* sel)))))))
           ;;(format t "ENTER :Q TO RUN WITH THE CHOSEN PARAMETERS, OR :C TO CONTINUE TWEAKING.~%~~ ")
;           (clear-input)
      ;;(when (eq (read) :Q) (return)))
      ;; setup was here
;;       (format t "THE EVOLUTION WILL RUN UNTIL EITHER A TARGET FITNESS IS~%")
;;       (format t "REACHED, OR A MAXIMUM NUMBER OF CYCLES HAS BEEN EXCEEDED.~%~%")
;;       (format t "ENTER TARGET FITNESS (A FLOAT BETWEEN 0 AND 1).~%~~ ")
;; ;      (clear-input)
;;       (setf target (read))
;;       (format t "~%CHOOSE A SELECTION METHOD: TOURNEMENT, ROULETTE, OR GREEDY-ROULETTE?~%ENTER :T, :R, or :G.~%~~ ")
;; ;      (clear-input)
;;       (setf *method-key* (read))
;;       (format t "
;; ENTER MAXIMUM NUMBER OF CYCLES (A CYCLE HAS TAKEN PLACE WHEN A
;; BREEDING EVENT HAS ELAPSED ON EACH ISLAND. IN TOURNMENT MODE, THIS
;; AMOUNTS TO TWO DEATHS, ONE INSTANCE OF SEXUAL REPRODUCTION, AND TWO
;; BIRTHS. IN ROULETTE MODE, THIS AMOUNTS TO N DEATHS, N/2 INSTANCES OF
;; SEXUAL REPRODUCTION, AND N BIRTHS, WHERE N = THE TOTAL POPULATION
;; COUNT).~%~~ ")
;; ;      (clear-input)
;;       (setf *rounds* (read))
;;       (format t "~%COMMENCING EVOLUTIONARY PROCESS. PLEASE STANDBY.~%~%"))))


(defun sanity-check ()
  "A place to prevent a few of the more disasterous parameter clashes
and eventually, sanitize the input."
  (when *debug*
    (setf *parallel* nil)))

;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

(defun main ()
  (parse-command-line-args)
  (when *menu* (menu))
  (sanity-check)
  (update-dependent-machine-parameters)
  (setf +ISLAND-RING+ '())
  (setup)
  (format t "COMMENCING EVOLUTIONARY PROCESS. PLEASE STANDBY.~%")
  (evolve :target *target* :rounds *rounds*))


;; todo: write a generic csv datafile->hashtable loader, for
;; deployment on arbitrary datasets. 

;; it's not convenient, yet, to select the VM at runtime. this choice needs
;; to be made at compile time, for the time being. 


