(in-package :genlin)

;;; This copy only exists for the sake of carefree tinkering. Eventually,
;;; it will be merged with r-machine.lisp, the difference between the two
;;; coming down to a choice of parameters.

(defparameter *machine* :stackmachine)


;;; %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;;; STACKMACHINE differs from SLOMACHINE primarily in programme design.
;;; I've switched back from arrays to lists as the canonical code-sequence
;;; representation. I've also redesigned the way in which machine code
;;; instructions are formalized. Each instruction is now, again, a function,
;;; but a function that only takes one argument: the instruction itself,
;;; from which it extracts the necessary information using dst? src? and
;;; so on. This lets me be much more versatile with the way in which
;;; instructions operate, without having to reduce everything to the same
;;; procrustean signature, or wrap every call in an ugly, ad hoc case or
;;; cond table. Use of external lexical variables is made possible by
;;; incorporating a few free variables into these functions -- marked with
;;; the sigil '%', for easy reading. These include, at present, %seq, %reg
;;; and %stk. In order to run any of these functions, they need to be
;;; enclosed in a lexical environment in which these variables are bound,
;;; and bound to values of the expected types (%reg is an array, while
;;; %seq and %stk are lists). (Note: there's also %skip, which is a boolean.
;;; It's set to T when a jump instruction prompts a jump, and nil otherwise.)
;;; %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
;; Declaim inline functions for speed
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

(declaim (inline guard-val))

(declaim (inline HLT JMP PSH PRG PEX PIN CMP LOD STO MOV DIV MUL XOR CNJ DIS PMD ADD SUB MUL JLE)) 

(declaim (inline exec))
         
;;(declaim (inline execute-sequence)) ;; ballsy. can't believe it worked.


;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
(defvar *operations*)

(defmacro src? (inst)
  "Returns the source address."
  `(ldb *srcbits* ,inst))

(defmacro dst? (inst)
  "Returns the destination address."
  `(ldb *dstbits* ,inst))

(defmacro op? (inst)
  "Returns the actual operation, in the case of register ops, in 
the form of a function."
  `(aref *operations* (ldb *opbits* ,inst )))

(defmacro opc? (inst)
  "Returns the numerical opcode."
  `(ldb *opbits* ,inst))

(defmacro jmp? (inst) ;; ad-hoc-ish...
  ;;(declare (type (unsigned-byte 64) inst))
  `(member (op? ,inst) *jump-ops-list*)) 

(defmacro nop? (inst)
  `(eq (op? ,inst) #'NOP))

;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
;; master update function for VM parameters
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

;; --- Operations: these can be tweaked independently of the 
;; --- fields above, so long as their are at least (expt 2 *opf*)
;; --- elements in the *operations* vector. 

;; NEW STRATEGY: USE FREE VARIABLES. USE THEM LIKE YOU STOLE THEM

(defvar %seq)

(defvar %reg)

(defvar %stk)

(defvar %pc)

(defvar %bin)

(defvar %skip)

(defvar %jmpflag)

(defvar %halt)

(defvar %ttl)

(defvar %pexflag)

(defmacro grd* (expr)
  `(guard-val ,expr *minval* *maxval*))

;; (defun exec (inst)
;;   (declare (type (unsigned-byte 64) inst))
;;   (declare (optimize (speed 3)))
;;   (declare (type (vector function) *operations*))
;;   (let ((opfunc (op? inst)))
;;     (declare (type function opfunc))
;;     (funcall opfunc inst)))

(defmacro exec (inst)
  `(funcall (op? ,inst) ,inst))

(defun test-exec (inst)
  (let ((%reg *initial-register-state*)
        (%seq `(,inst))
        (%stk '()))
    (format t "SRC: R~D = ~F~%DST: R~D = ~F~%OP:  ~A~%"
            (src? inst) (elt %reg (src? inst))
            (dst? inst) (elt %reg (dst? inst))
            (func->string (op? inst)))
    (exec inst)))

(defun MOV (inst)
  "Copy the contents in SRC to register DST."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst)) (elt %reg (src? inst))))


(defun LEA (inst)
  "Load the SRC address argument directly into DST register."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst)) (src? inst)))


(defun DIV (inst)
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (grd* (divide (elt %reg (dst? inst))
                      (elt %reg (src? inst))))))

(defun XOR (inst) ;; xor integer parts
  "Performs a bitwise XOR on SRC and DST, storing the result in DST."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (logxor (floor (elt %reg (dst? inst)))
                (floor (elt %reg (src? inst))))))

(defun CNJ (inst)
  "Performs a bitwise AND on SRC and DST, storing the result in DST."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (logand (floor (elt %reg (dst? inst)))
                (floor (elt %reg (src? inst))))))

(defun DIS (inst)
  "Performs a bitwise OR on SRC and DST, storing the result in DST."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (logior (floor (elt %reg (dst? inst)))
                (floor (elt %reg (src? inst))))))

(defun PMD (inst)
  "Performs a protected SRC MOD DST, storing the result in DST."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (if (zerop (elt %reg (dst? inst)))
            0
            (mod (elt %reg (src? inst))
                 (elt %reg (dst? inst))))))

(defun ADD (inst)
  "Adds the rational-valued contents of SRC and DST, storing result in DST."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (+ (elt %reg (src? inst))
           (elt %reg (dst? inst)))))

(defun SUB (inst)
  "Subtracts DST from SRC, storing the value in DST."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (grd* (- (elt %reg (src? inst))
                 (elt %reg (dst? inst))))))


(defun HLT (inst)
  (declare (ignore inst))
  (setf %ttl 0))

(defun MUL (inst)
  "Multiplies SRC and DST, storing the value in DST."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (grd* (* (elt %reg (src? inst))
                 (elt %reg (dst? inst))))))

(defun CMP (inst)
  "Skip the next instruction if val in first reg <= val in second."
  (declare (type (unsigned-byte 64) inst))
  (if (<= (elt %reg (src? inst)) (elt %reg (dst? inst)))
      (setf %jmpflag T)))

(defun JLE (inst)
  "Skip the next instruction if val in first reg <= val in second."
  (declare (type (unsigned-byte 64) inst))
  (if (<= (elt %reg (src? inst)) (elt %reg (dst? inst)))
      (setf %skip T)))

;; New jumping instructions

(defun JMP (inst)
  "If %jmpflag is set, then jump forwards or backwards n lines."
  (let ((n (ldb (byte *wordsize* 0) (ash inst (- (1+ *opcode-bits*)))))
        (d (expt -1
                 (logand 1 (ash inst (- *opcode-bits*))))))
    (when %jmpflag
      (setf %pc (mod (+ (* n d) %pc) (length %seq)))
      (setf %jmpflag nil))))
  
  
;; changing lod/sto so that they operate on the stack instead
;; of on the code segment, so that we can recover intron detection
(defun LOD (inst)
  "Stub. Really just here for consistent pretty printing."
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (if (null %stk)
            0
            (elt %stk (safemod (floor (elt %reg (src? inst)))
                               (length %stk))))))

(defun STO (inst)
  "Stub. Really just here for consistent pretty printing."
  (declare (type (unsigned-byte 64) inst))
  (let ((stuff (ldb (byte *wordsize* 0) (floor (elt %reg (src? inst))))))
    (if (null %stk)
        (push stuff %stk)
        (setf (elt %stk (safemod (floor (elt %reg (dst? inst)))
                                 (length %stk)))
              (ldb (byte *wordsize* 0) (floor (elt %reg (src? inst))))))))

(defun PRG (inst) ;; pop to register
  (declare (type (unsigned-byte 64) inst))
  (setf (elt %reg (dst? inst))
        (nil0 (pop %stk))))

(defun PSH (inst)
  (declare (type (unsigned-byte 64) inst))
  (push (elt %reg (src? inst)) %stk))

;; but PEX still introduces arbitrary code execution, which
;; prevents any sort of definitive intron detection -- but then,
;; does it matter? Is anything lost if introns are only approximately
;; introns, potentially activated by epigenetic factors?
;; Biology got away with it. 
(defun PEX (inst) ;; pop to execute
  (declare (ignore inst))
  (setf %pexflag t)
  (exec (floor (abs (nil0 (pop %stk))))))

(defun PIN (inst)
  (declare (type (unsigned-byte 64) inst))
  (push (elt %seq
             (safemod (floor (elt %reg
                                  (src? inst))) (length %seq)))
        %stk))

;; module building instructions. Focussing on using just ONE module for
;; now, but this could be extended to a linked list or array of modules. 
(defun BIN (inst)
  "Grabs an instruction (+/-) n steps away and pushes it into %module.
Fetching mechanism is relative, like JMP's jumping mechanism, as
opposed to LOD and STO's absolute instruction location mechanism."
  (declare (type (unsigned-byte 64) inst))
  (let ((n (ldb (byte *wordsize* 0) (ash inst (- (1+ *opcode-bits*)))))
        (d (expt -1
                 (logand 1 (ash inst (- *opcode-bits*))))))
    (push (elt %seq (mod (* n d) (length %seq))) %module)))

(defun CLR (inst)
  (declare (ignore inst))
  (setf %bin nil))
             
(defun CAL (inst)
  (declare (ignore inst))
  (loop for m-inst in %bin do
       (decf %ttl)   ;; since loops can form in modules, via bin
       (exec m-inst))) ;; even if JMP will still return you to %seq

(defun NOP (inst)
  (declare (ignore inst)))

;; just go ahead and use free variables 
;; (defun PPR (&rest args)
;;   "

(defparameter *reg-ops-list*
  `(,#'ADD ,#'MUL ,#'SUB ,#'DIV
         ,#'PMD ,#'XOR ,#'CNJ ,#'DIS ,#'MOV))

(defparameter *imm-ops-list*
  `(,#'LEA))

(defparameter *jump-ops-list*
  `(,#'JLE ,#'JMP ,#'CMP))

(defparameter *load-ops-list*
  `(,#'LOD))

(defparameter *store-ops-list*
  `(,#'STO))

(defparameter *absolute-ops-inst*
  `(,#'HLT))

(defparameter *module-ops-inst*
  `(,#'BIN ,#'CLR ,#'CAL))

(defparameter *stack-ops-list*
  `(,#'PSH ,#'PEX ,#'PRG ,#'PIN))

;; suggestion: prepare some combos that can be selected from at runtime.
;; (using command line options, e.g.)
(defparameter *slomachine-ops-list*
  (concatenate 'vector
               (subseq *reg-ops-list* 0 5)
               *jump-ops-list*
               *load-ops-list*
               *store-ops-list*))

(defparameter *NOP-INST* 0) 

(defparameter *suggested-ops-list*
  `(,#'ADD ,#'MUL ,#'SUB ,#'DIV ,#'PMD
           ,#'PSH ,#'PRG ,#'CMP ,#'JMP
           ,#'LEA ,#'BIN ,#'CAL ,#'CLR
           ,#'MOV ,#'XOR ,#'NOP ,#'NOP))

;; (setf *operations*
;;       (remove-if #'null (concatenate 'vector
;;                                      `(,#'NOP)
;;                                      *reg-ops-list*
;;                                      ;;          *load-ops-list*
;;                                      ;;          *store-ops-list*
;;                                      *stack-ops-list*
;;                                      *jump-ops-list*
;;                                      *imm-ops-list*
;;                                      (loop repeat (expt 2 *opcode-bits*)
;;                                         collect #'NOP))))

(setf *operations* (coerce *suggested-ops-list* 'vector))

                                 ;;*jump-ops-list*
                                 ;;*load-ops-list*
                                 ;;*store-ops-list*)))


(defparameter *reg-op-keys*
  '(:DIV :MUL :SUB :ADD :PMD :XOR :CNJ :DIS :MOV))

(defparameter *jmp-op-keys*
  '(:JLE))

(defparameter *store-op-keys*
  '(:STO))

(defparameter *load-op-keys*
  '(:LOD))

(defvar *operation-keys*)

(defun shuffle-operations ()
  (setf *operations* (coerce (shuffle (coerce *operations* 'list)) 'vector)))


(defvar *intron-flag*)
;; this whole thing should be refactored out of slomachine and r-machine,
;; to a more central location
(defun update-dependent-machine-parameters ()

;; Not quite ready yet. 

  (unless *ttl*
    (setf *ttl* *max-len*))
  
  (setf *destination-register-bits*
         (max (ceiling (log (how-many-output-registers?) 2))
              *destination-register-bits*))

   (setf *source-register-bits*
         (max (ceiling (log (+ (how-many-input-registers?)
                               (how-many-output-registers?)) 2))
              *source-register-bits*))
  
  (setf *wordsize*
        (+ *opcode-bits* *source-register-bits*
           *destination-register-bits*))
  ;; NB: there is one extra bit past the wordsize, where the intron flag
  ;; is stored. we leave it outside the wordsize range so that randomly
  ;; generated instructions aren't marked as introns in mutations or
  ;; spawning functions. but double check where wordsize is used. 
  (setf *intron-flag*
        (ash 1 *wordsize*))

  (setf *machine-fmt* (format nil "~~~D,'0b  ~~a" *wordsize*))
  
  (setf *max-inst*
    (expt 2 *wordsize*)) ;; upper bound on inst size
  
  (setf *opbits*
    (byte *opcode-bits* 0))
  
  (setf *srcbits*
    (byte *source-register-bits* *opcode-bits*))
  
  (setf *dstbits*
        (byte *destination-register-bits*
              (+ *source-register-bits* *opcode-bits*)))

  (setf *default-input-reg*
        (concatenate 'vector
               (loop for i from 1 to (- (expt 2 *source-register-bits*)
                                        (expt 2 *destination-register-bits*))
                  collect (expt -1 i))))

  (setf *default-registers*
        (concatenate 'vector #(0) (loop for i from 2 to
                                       (expt 2 *destination-register-bits*)
                                     collect 0 )));; (expt -1 i))))
  
  (setf *pc-idx*
        (+ (length *default-registers*) (length *default-input-reg*)))
  
  (setf *initial-register-state*
        (concatenate 'vector
                     *default-registers*
                     *default-input-reg*
                     #(0))) ;; PROGRAMME COUNTER

  (setf *input-start-idx* (length *default-registers*))

  (setf *input-stop-idx*
      (+ *input-start-idx* (length *default-input-reg*))))

;;(update-dependent-machine-parameters)

;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
;; Functions for extracting fields from the instructions
;; and other low-level machine code operations.
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

;; history is not threadsafe. does it matter? not much, since it's
;; only used in debugging mode, when *parallel* is set to nil. 
(defparameter =history=
  (let ((hist '())
        (warning t))          
    (lambda (&optional (entry nil))
      (when (and *parallel* warning)
        (format t "***  WARNING: HISTORY IS NOT THREADSAFE  ***~%")
        (format t "*** SET *PARALLEL* TO NIL WHEN DEBUGGING ***~%")
        (setf warning nil))
      (cond ((eq entry 'FLUSH) (setf hist '()))
            ((eq entry 'ALL) hist)
            (entry (push entry hist))
            (t (car hist))))))

(defun history-push-test (seq reg)
  (funcall =history= (cons seq reg)))

(defun history-flush ()
  (funcall =history= 'FLUSH))

(defun history-print (&optional len)
  (let ((h (funcall =history=)))
    (print (subseq h 0 len))))

(defparameter *comments* t)

(defun disassemble-history (&key (all 'all) (len 1) (static nil)
                              (comments *comments*))
  "If passed a sequence in the static field, disassemble it without
any reference to register states. If not, disassemble the last len
entries in the history stack, tracking changes to the registers."
  (labels ((strip-parens (str)
             (remove #\( (remove #\) str)))
           (reg-op-comment (inst line)
             (format t " ;; now R~d = ~f; R~d = ~f~%" 
                     (src? inst)
                     (elt (getf line :reg) (src? inst))
                     (dst? inst)
                     (elt (getf line :reg) (dst? inst))))
           (jmp-op-comment (inst line)
             (format t " ;; R~d = ~5,2F  R~d = ~5,2F, flag = ~a, pc = ~d~%"
                     (src? inst) (elt (getf line :reg) (src? inst))
                     (dst? inst) (elt (getf line :reg) (dst? inst))
                     (getf line :jmpflag) (getf line :pc)))
             
           (lod-op-comment (inst line)
             (let* ((addr (mod (floor
                                (elt (getf line :reg) (src? inst)))
                               (length (getf line :seq))))
                    (data (elt (getf line :seq) addr))
                    (regnum (dst? inst)))
               (format t " ;; loading ~d from @~d into R~d~%"
                       data addr regnum)))
           (sto-op-comment (inst line)
             (let* ((addr (mod (floor (elt (getf line :reg) (dst? inst)))
                               (length (getf line :seq))))
                    (data (ldb (byte *wordsize* 0)
                               (floor (elt (getf line :reg)
                                           (src? inst)))))
                    (regnum (src? inst)))
               (format t " ;; storing ~d from R~d in @~d~%"
                       data regnum addr)
               (when (>= addr (getf line :pc))
                 (format t "*** SEQUENCE REWRITING ITSELF ***~%"))))
           (bin-op-comment (inst line)
             (let ((bin (getf line :bin)))
               (format t " ;; BIN: ~A~%" bin)))
           (stk-op-comment (inst line)
             (let* ((stack (getf line :stk)))
                   ;; (stack (if (null stk) '(0) stk)))
               (format t " ;; STACK TOP: ~A~A~%"
                       (strip-parens
                        (format nil "~A"
                                (mapcar #'(lambda (x) (float (nil0 x)))
                                        (subseq stack 0 (min
                                                         (length stack)
                                                         5)))))
                       (if (> (length stack) 5) "..." ""))
               (when (and (not (null (car stack)))
                          (equalp (op? inst) #'PEX))
                          (format t "PEX >>  ~A~%"
                                  (inst->string (floor (car stack)))))))
           (imm-op-comment (inst line)
             (declare (ignore line))
             (format t "  ;; LOADING ~D IN R~D~%"
                     (src? inst) (dst? inst))))
    (let* ((history (funcall =history= all))
           (story (if static
                      (coerce static 'list)
                      (reverse (subseq history 0 len)))))
      (loop for line in story do
           (let ((inst (if static line (getf line :inst))))
             (format t *machine-fmt* ;; needs to be made flexible. 
                     inst
                     (inst->string inst))
             (when (and comments (not static)) (format t "  (~d) " (getf line :pc))
                   (cond ((member (op? inst) *reg-ops-list*)
                          (reg-op-comment inst line))
                         ((member (op? inst) *jump-ops-list*)
                          (jmp-op-comment inst line))
                         ((member (op? inst) *load-ops-list*)
                          (lod-op-comment inst line))
                         ((member (op? inst) *store-ops-list*)
                          (sto-op-comment inst line))
                         ((member (op? inst) *stack-ops-list*)
                          (stk-op-comment inst line))
                         ((member (op? inst) *imm-ops-list*)
                          (imm-op-comment inst line))
                         ((member (op? inst) *module-ops-list*)
                          (bin-op-comment inst line))
                         (t (format t " ;; ¯\_(ツ)_/¯~%"))))
             (if (or static (not comments)) (format t "~%"))))
      (if static (hrule)))))

;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
;; The engine room
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=



(defun execute-sequence (seq &key (registers *initial-register-state* )
                               (input *default-input-reg*)
                               (stack nil)
                               (output nil)
                               (debug nil))
  "Takes a sequence of instructions, seq, and an initial register
state vector, registers, and then runs the virtual machine, returning
the resulting value in the registers indexed by the integers in the
list parameter, output."
  (declare (type fixnum *input-start-idx* *pc-idx*)
           (type (cons integer) output)
           (type (or null (cons (unsigned-byte 64))) seq)
           (type (or null cons) stack)
           (type (simple-array real 1) input registers))
;;           (optimize (speed 3)))
  (flet ((save-state (inst &key reg seq stk bin skip pc pexflag jmpflag)
           (declare (type (simple-array real 1) reg)
                    (type boolean skip)
                    (type function =history=))
           (funcall =history= (list :inst inst
                                    :reg reg
                                    :seq seq
                                    :skip skip
                                    :stk stk
                                    :bin bin
                                    :jmpflag jmpflag
                                    :pexflag pexflag
                                    :pc pc))))
    (let ((%seq (coerce seq 'vector)) ;; shouldn't be more pricey than copy
          (%reg (copy-seq registers))
          (%pc 0) ;; why bother putting the PC in the registers?
          (%ttl (* (length seq) 5))
          (%jmpflag nil)
          (%skip nil)
          (%module nil)
          (inst)
          (%pexflag t)
          (%stk (copy-seq stack))
;;;          (seqlen (length seq))
          (debugger (or debug *debug*)))
      ;; so that we can have our junk DNA back.
      (declare (type (simple-array real 1) %reg)
               (type boolean debugger)
               (ignorable %jmpflag)
               (type fixnum %pc))
      ;; the input values will be stored in read-only %reg
      (setf (subseq %reg *input-start-idx*
                    (+ *input-start-idx* (length input))) input)
      (loop
         while (< %pc (length %seq))
         while (> %ttl 0) do
           (setf inst (aref %seq %pc))
           (incf %pc) ;; not truly necessary. may suppress for speed. 
           (decf %ttl)
           (cond ((or %skip
                      (and (intron? inst)
                           %pexflag)) ;; missing the efficiency point now. 
                  (setf %skip nil))
                 (:DEFAULT 
                  (exec inst)
                     (and debugger (save-state inst
                                               :reg %reg
                                               :seq %seq
                                               :bin %bin
                                               :skip %skip
                                               :pexflag %pexflag
                                               :jmpflag %jmpflag
                                               :stk %stk
                                               :pc %pc)
                          (disassemble-history)))))

      (and *debug* (hrule) (history-flush))
      (mapcar #'(lambda (i) (aref %reg i)) output))))


;; ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
;; Intron Removal
;; ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

(defun mark-intron-bit (inst)
  (ldb (byte (1+ *wordsize*) 0) (logior inst *intron-flag*)))

(defun intron? (inst)
  (= 1 (ash inst (- *wordsize*))))

(defun remove-introns (seq &key (output '(0)))
  "Filters out non-effective instructions from a sequence -- instructions
that have no bearing on the final value(s) contained in the output 
register(s)."
  ;; NB: When code is r/w w LOD, STO, then remove-introns cannot be expected
  ;; to return reliable results.
  ;; we can test sensitivity of LOD/STO instructions to input. If there are
  ;; either no LOD/STO instructions, or if the LOD/STO instructions are in-
  ;; sensitive to input, then EFF can be extracted in the usual fashion.
  ;; Creatures whose control flow is contingent on input via LOD/STO should be
  ;; flagged or logged, just out of curiosity, and to gather statistics on
  ;; their frequency. 
  (let ((efr output)
        (nopops nil)
        (nocmps nil)
        (efseq '()))
    ;; Until I code up a good, efficient way of finding entrons in
    ;; a piece of potentially self-modifying code, this will have to do:
    (cond (*remove-introns*
           (loop for i from (1- (length seq)) downto 0 do
             (let ((inst (elt seq i)))
               (cond ((and (not (nop? inst))
                           (or (member (dst? inst) efr)
                               (jmp? inst)))
                      (push (src? inst) efr)
                      (push inst efseq))
                      (:DEFAULT (push (mark-intron-bit inst) efseq)))))
           ;; if no CMP instructions, mark all JMP instructions as introns
           (setf nocmps
                 (not (some #'(lambda (x) (eq (op? x) #'CMP)) efseq)))
           (setf nopops
                 (not (some #'(lambda (x) (member (op? x) `(,#'PEX
                                                       ,#'PRG))) efseq)))
           (when (or nocmps nopops)
             (loop for inst in efseq do
                  (when (and nocmps (jmp? inst))
                    (nsubst (mark-intron-bit inst) inst efseq))
                  (when (and nopops (eq (op? inst) #'PSH))
                    (nsubst (mark-intron-bit inst) inst efseq)))))
           (:DEFAULT (setf efseq seq)))
    efseq))

;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
;; debugging functions
;; =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  
(defun print-registers (registers)
  (loop for i from 0 to (1- (length registers)) do
       (format t "R~d: ~6f ~c" i (aref registers i) #\TAB)
       (if (= 0 (mod (1+ i) 4)) (format t "~%")))
  (format t "~%"))

(defun inst->string (inst)
  (concatenate 'string
               (format nil "[~a  R~d, R~d]"
                       (func->string (op? inst))
                       (src? inst) (dst? inst))))


(defun disassemble-sequence (seq &key (registers *initial-register-state*)
                                   (input *default-input-reg*)
                                   (static nil))
  (if static (disassemble-history :static seq)
      (execute-sequence seq :debug t :input input :registers registers)))

