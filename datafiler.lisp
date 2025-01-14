;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
;; Data reading functions
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

;;(defpackage :genlin
;;  (:use :common-lisp))

(in-package #:genlin)

;; moved here from params. may cause bug. 
(defparameter =label-scanner=
  ;; Enumerates labels, keeping track of labels it's already seen. 
  (let ((seen '()))
    (lambda (lbl)
      (cond ((eq lbl 'flush) (setf seen '()))
            ((not (member lbl seen :test #'equalp)) (push lbl seen)))         
      (cond ((eq lbl 'get) (pop seen) (reverse seen)) ;; return seen, w/o 'get
            ((eq lbl 'count) (pop seen) (length seen))
            (t (position lbl (reverse seen) :test #'equalp :from-end t))))))


(defun parse-numeric-csv-key (k)
  (coerce (mapcar #'rational
                  (read-from-string
                   (concatenate 'string "("
                                (substitute #\space #\, k) ")")))
          'vector))


(defun data-hash (line ht)
  (let* ((kv (split-at-label line))
         (raw-k (car kv))
         (raw-v (cdr kv))
         (val (funcall =label-scanner= raw-v))
         (key (parse-numeric-csv-key raw-k)))
    (setf (gethash key ht) val)))

(defun set-out-reg ()
  (setf *out-reg*
        (loop for i from 0 to (1- (length (funcall =label-scanner= 'get)))
           collect i)))

(defun datafile->hashtable (&key filename (rescaler *scale-data*))
  
  (cond ((eq *dataset* :tictactoe)
         (ttt-datafile->hashtable :filename filename))
        (t (format t "[+] PATH TO DATA: ~a~%" filename)
           (let ((ht (make-hash-table :test 'equal))
                 (input (open filename :if-does-not-exist nil)))
             (when input
               (loop
                  for line = (read-line input nil)
                  while line do
                    (data-hash line ht)
                    (and *debug* (format t "READ|  ~a~%" line)))
               (close input))
             (case rescaler
               ((:mean-variance)
                (rescale-data ht
                              :scaling-function
                              #'listwise-mean-variances))
               ((:linear-transform)
                (rescale-data ht
                              :scaling-function
                              #'listwise-linear-transforms))
               (otherwise ht))))))

(defun attribute-string (vec)
  (let ((str ""))
    (loop for i from 1 to (length vec) do
         (setf str (concatenate 'string str
                                (format nil "ATTRIBUTE ~@R:~C~F~%"
                                        i #\Tab (aref vec (1- i)))))) str))

(defun ugly-max-array (arr)
  (reduce #'max (loop for i in
                     (loop for k below
                          (apply #'* (array-dimensions arr))
                        collect (row-major-aref arr k)) collect i)))


(defun build-confusion-matrix (classes)
  (make-array `(,(length classes) ,(length classes)) :initial-element 0))
  

(defun print-confusion-matrix (cm &optional (stream *standard-output*))
  (let* ((s (ugly-max-array cm))
         (names (mapcar #'string-upcase (funcall =label-scanner= 'get)))
         (fmt (format nil "~~~dd" (+ 2 (ceiling (log s 10)))))
         (longest (reduce #'max (mapcar #'length names)))
         (padded-names (mapcar
                        #'(lambda (x) (concatenate
                                  'string x
                                  (loop repeat (- longest
                                                  (length x))
                                     collect #\space))) names)))
    
           (loop for row from 0 below (car (array-dimensions cm)) do
                (format stream "~A  " (elt padded-names row))
                (loop for col from 0 below (cadr (array-dimensions cm)) do  
                     (format stream fmt (aref cm col row)))
                (terpri))))




;; use the helper functions in the fitness section in here, instead. 
(defun data-classification-report  (&key (crt *best*) (ht) (out)
                                      (verbose *verbose-report*)
                                      (artfunc #'attribute-string))
  (let ((cm (build-confusion-matrix out))
        (correct 0)
        (incorrect 0)
        (names (mapcar #'string-upcase (funcall =label-scanner= 'get)))
        (failures '()))
    (loop for k being the hash-keys in ht using (hash-value v) do
         (let* ((output (mapcar #'abs (execute-creature crt
                                                        :debug verbose
                                                        :input k
                                                        :output out)))
                (vote (register-vote output))
                (success (= vote v))
                (certainties
                 (mapcar #'(lambda (x) (divide x (reduce #'+ output))) output)))
           
           
           (incf (aref cm vote v)) ;; confusion matrix entry
           (if success (incf correct) (progn
                                        (incf incorrect)
                                        (push k failures)))
           (when verbose
             (hrule)
             (format t "~A~%" (funcall artfunc k))
             (terpri)
             (loop for i from 0 to (1- (length output)) do
                  (format t "CLASS ~A: ~5,2f %~%" (elt names i)
                        (* 100 (elt certainties i))))
             (cond (success
                    (when verbose
                      (format t "~%CORRECTLY CLASSIFIED AS ~A~%"
                                        (elt names v))))
                   ((not success)
                    (when verbose
                      (format t "~%INCORRECTLY CLASSIFIED. ")
                      (format t "WAS ACTUALLY ~A~%"
                              (elt names v)))))
             (hrule))))
           (when verbose
             (format t "                            ~@(~R~) Failures:~%"
                     (length failures))
             (hrule)
             (loop for fail in failures do
                  (format t "CLASS: ~A~%VECTOR: ~a~%"
                          (elt names (gethash fail ht)) fail)
                  (format t "~%~A" (funcall artfunc fail))
                  (hrule)))
           (format t "TOTAL CORRECT:   ~d~%TOTAL INCORRECT: ~d~%"
            correct incorrect)
    (hrule)
    (format t "CONFUSION MATRIX: ROW = TRUE CLASS, COLUMN = GUESSED CLASS~%")
    (hrule)
    (print-confusion-matrix cm)
    (format t "~%DETECTION RATE: ~5,2F%~%"
            (* 100 (cmatrix->detection-rate cm)))
    (format t "ACCURACY:       ~5,2F%~%"
            (* 100 (cmatrix->accuracy cm)))
    (hrule)
;;    (format t "AGGREGATE CONFUSION MATRIX OF ISLAND-RING:~%~%")
;;    (print-confusion-matrix (cmatrix-sum-of-island-ring +island-ring+))
    (values (cons correct incorrect)
            failures)))

;; moved over here from genlin.lisp:

(defun partition-data (hashtable ratio &key (first-part-only nil))
  ;; need to modify this so that the distribution of values in the test
  ;; set is at least similar to the distribution of values in the training
  (let* ((size (hash-table-count hashtable))
         (training (make-hash-table :test 'equalp))
         (testing (make-hash-table :test 'equalp))
         (keys (shuffle (loop for k being the hash-keys in hashtable collect k)))
         (vals)
         (keys-by-val)
         (portions))
    (setf vals (remove-duplicates (loop
                                     for v being the hash-values
                                     in hashtable collect v)))
    (setf keys-by-val (loop for v in vals collect
                           (remove-if-not
                            #'(lambda (x) (equalp (gethash x hashtable) v))
                            keys)))
    (loop
       for klist in keys-by-val do
           (push (round (* ratio  size  (/ (length klist)
                                           size)))
                 portions))
    (setf portions (reverse portions))
    (and *debug* (format t "TOTAL COUNT OF SPECIMENS: ~D~%CLASS COUNTS: ~A~%PORTIONS FOR TRAINING, BY CLASS: ~A~%"
                         size (mapcar #'length keys-by-val) portions))
    (loop
       for keylist in keys-by-val
       for portion in portions do
         (if (some #'null keylist) (format t "FOUND NULL IN ~A~%" keylist))
         (loop for i from 1 to portion do
              (let ((k))
                (setf k (pop keylist))
                (setf (gethash k training)
                      (gethash k hashtable))))
         (unless first-part-only
           (loop for k in keylist do
                (setf (gethash k testing)
                      (gethash k hashtable)))))
    (cons training testing)))


;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

;; is there any reason why I'm using vecs instead of lists for
;; the ht keys?

(defun listwise-sums (list-of-lists &key (pre nil))
  (when (null pre)
    (setf pre (lambda (x) x))) ;; set pre to nop if nil
  (reduce #'(lambda (x y) ;; create list of abs sums
              (mapcar #'(lambda (a b) (+ (funcall pre a) (funcall pre b)))
                      x y)) list-of-lists))

(defun listwise-means (list-of-lists)
  (mapcar #'(lambda (x) (divide x (length list-of-lists)))
          (listwise-sums list-of-lists :pre #'abs)))

(defun listwise-variances (list-of-lists)
  (let* ( (meanlist (listwise-means list-of-lists))
         (deviations (mapcar #'(lambda (l) (mapcar #'- l meanlist))
                             list-of-lists))
         (devmeans (listwise-means deviations))
         (variancelists (loop for klist in list-of-lists collect
                             (mapcar #'(lambda (x y) (expt (- x y) 2))
                                     klist devmeans)))
         (variances (listwise-means variancelists)))
    variances))

(defun listwise-stddevs (list-of-lists)
  (mapcar #'(lambda (x) (expt x 1/2)) (listwise-variances list-of-lists)))
         

(defun listwise-mean-variances (list-of-lists)
  (let ((meanlist (listwise-means list-of-lists))
        (devilist (listwise-stddevs list-of-lists)))
  (loop for list in list-of-lists collect
       (mapcar #'(lambda (x y z)
                   (divide (- x y) z))
               list meanlist devilist))))


(defun listwise-maxima (list-of-lists)
  (reduce #'(lambda (x y) ;; create list of abs sums
              (mapcar #'max x y)) list-of-lists))

(defun listwise-minima (list-of-lists)
  (reduce #'(lambda (x y) ;; create list of abs sums
              (mapcar #'min x y)) list-of-lists))

(defun listwise-linear-transforms (list-of-lists)
  (let* ((maxes (listwise-maxima list-of-lists))
         (mins (listwise-minima list-of-lists))
         (rescaled (loop for list in list-of-lists collect
                        (mapcar #'(lambda (initial maximum minimum)
                                    (divide (- initial minimum)
                                            (- maximum minimum)))
                                list maxes mins))))
         rescaled))

(defun listwise-scale-by (list-of-lists factor)
  (loop for list in list-of-lists collect
       (mapcar #'(lambda (x) (* x factor)) list)))

(defun rescale-data (ht &key (scaling-function
                              #'listwise-linear-transforms)
                          (scaling-factor 8))
  (let* ((newht (make-hash-table))
         (kvecs (loop for k being the hash-keys in ht collect k))
         (klists (mapcar #'(lambda (x) (coerce x 'list)) kvecs))
         (rescaled (listwise-scale-by
                    (funcall scaling-function klists)
                    scaling-factor)))
    (mapcar #'(lambda (x y) (setf (gethash (coerce x 'vector) newht)
                             (gethash y ht)))
            rescaled kvecs)
    (format t "[+] RESCALED DATA USING ~A~%"
            (func->string scaling-function))
    newht))



(defun count-labels (ht)
  (let ((counts '())
        (tally 0)
        (lastseen))
    (loop for val in
         (sort (loop for v being the hash-values in ht collect v) #'<) do
         (unless (or (null lastseen) (= val lastseen))
           (push tally counts)
           (setf tally 0))
         (incf tally)
         (setf lastseen val))
    (push tally counts)
    counts))
