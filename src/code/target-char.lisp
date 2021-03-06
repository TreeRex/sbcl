;;;; character functions

;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; This software is derived from the CMU CL system, which was
;;;; written at Carnegie Mellon University and released into the
;;;; public domain. The software is in the public domain and is
;;;; provided with absolutely no warranty. See the COPYING and CREDITS
;;;; files for more information.

(in-package "SB!IMPL")

;;; We compile some trivial character operations via inline expansion.
#!-sb-fluid
(declaim (inline standard-char-p graphic-char-p alpha-char-p
                 upper-case-p lower-case-p both-case-p alphanumericp
                 char-int))
(declaim (maybe-inline digit-char-p digit-weight))

(deftype char-code ()
  `(integer 0 (,char-code-limit)))

#!+sb-unicode
(progn
 (defvar *unicode-character-name-database*)
 (defvar *unicode-character-name-huffman-tree*))

(macrolet
    ((frob ()
       (flet ((file (name type)
                (merge-pathnames (make-pathname
                                  :directory
                                  '(:relative :up :up "output")
                                  :name name :type type)
                                 sb!xc:*compile-file-truename*))
              (read-ub8-vector (pathname)
                (with-open-file (stream pathname
                                        :direction :input
                                        :element-type '(unsigned-byte 8))
                  (let* ((length (file-length stream))
                         (array (make-array
                                 length :element-type '(unsigned-byte 8))))
                    (read-sequence array stream)
                    array))))
         (let ((character-database (read-ub8-vector (file "ucd" "dat")))
               (decompositions (read-ub8-vector (file "decomp" "dat")))
               (long-decompositions (read-ub8-vector (file "ldecomp" "dat"))))
           `(progn
              (declaim (type (simple-array (unsigned-byte 8) (*)) **character-database** **character-decompositions** **character-long-decompositions**))
              (defglobal **character-database** ,character-database)
              (defglobal **character-decompositions** ,decompositions)
              (defglobal **character-long-decompositions** ,long-decompositions)
              (defglobal **character-primary-compositions**
                (let ((table (make-hash-table))
                      (info ,(read-ub8-vector (file "comp" "dat"))))
                  (flet ((code (j)
                           (dpb (aref info (* 4 j))
                                (byte 8 24)
                                (dpb (aref info (+ (* 4 j) 1))
                                     (byte 8 16)
                                     (dpb (aref info (+ (* 4 j) 2))
                                          (byte 8 8)
                                          (aref info (+ (* 4 j) 3)))))))
                    (dotimes (i (/ (length info) 12) table)
                      (setf (gethash (dpb (code (* 3 i)) (byte 21 21)
                                          (code (1+ (* 3 i))))
                                     table)
                            (code-char (code (+ (* 3 i) 2))))))))
              (defun !character-database-cold-init ()
                (setf **character-database** ,character-database))
              ,(with-open-file (stream (file "ucd-names" "lisp-expr")
                                       :direction :input
                                       :element-type 'character)
                               (let ((names (make-hash-table)))
                                 #!+sb-unicode
                                 (loop
                                       for code-point = (read stream nil nil)
                                       for char-name = (string-upcase (read stream nil nil))
                                       while code-point
                                       do (setf (gethash code-point names) char-name))
                                 (let ((tree
                                        #!+sb-unicode
                                         (make-huffman-tree
                                          (let (list)
                                            (maphash (lambda (code name)
                                                       (declare (ignore code))
                                                       (push name list))
                                                     names)
                                            list)))
                                       (code->name
                                        (make-array (hash-table-count names)
                                                    :fill-pointer 0))
                                       (name->code nil))
                                   (maphash (lambda (code name)
                                              (vector-push
                                               (cons code (huffman-encode name tree))
                                               code->name))
                                            names)
                                   (setf name->code
                                         (sort (copy-seq code->name) #'< :key #'cdr))
                                   (setf code->name
                                         (sort (copy-seq name->code) #'< :key #'car))
                                   (setf names nil)
                                   `(defun !character-name-database-cold-init ()
                                      #!+sb-unicode
                                      (setq *unicode-character-name-database*
                                            (cons ',code->name ',name->code)
                                            *unicode-character-name-huffman-tree* ',tree))))))))))
  (frob))
#+sb-xc-host (!character-name-database-cold-init)

(defparameter *base-char-name-alist*
  ;; Note: The *** markers here indicate character names which are
  ;; required by the ANSI specification of #'CHAR-NAME. For the others,
  ;; we prefer the ASCII standard name.
  '((#x00 "Nul" "Null" "^@")
    (#x01 "Soh" "^a")
    (#x02 "Stx" "^b")
    (#x03 "Etx" "^c")
    (#x04 "Eot" "^d")
    (#x05 "Enq" "^e")
    (#x06 "Ack" "^f")
    (#x07 "Bel" "Bell" "^g")
    (#x08 "Backspace" "^h" "Bs") ; *** See Note above
    (#x09 "Tab" "^i" "Ht") ; *** See Note above
    (#x0A "Newline" "Linefeed" "^j" "Lf" "Nl") ; *** See Note above
    (#x0B "Vt" "^k")
    (#x0C "Page" "^l" "Form" "Formfeed" "Ff" "Np") ; *** See Note above
    (#x0D "Return" "^m" "Cr") ; *** See Note above
    (#x0E "So" "^n")
    (#x0F "Si" "^o")
    (#x10 "Dle" "^p")
    (#x11 "Dc1" "^q")
    (#x12 "Dc2" "^r")
    (#x13 "Dc3" "^s")
    (#x14 "Dc4" "^t")
    (#x15 "Nak" "^u")
    (#x16 "Syn" "^v")
    (#x17 "Etb" "^w")
    (#x18 "Can" "^x")
    (#x19 "Em" "^y")
    (#x1A "Sub" "^z")
    (#x1B "Esc" "Escape" "^[" "Altmode" "Alt")
    (#x1C "Fs" "^\\")
    (#x1D "Gs" "^]")
    (#x1E "Rs" "^^")
    (#x1F "Us" "^_")
    (#x20 "Space" "Sp") ; *** See Note above
    (#x7f "Rubout" "Delete" "Del")
    (#x80 "C80")
    (#x81 "C81")
    (#x82 "Break-Permitted")
    (#x83 "No-Break-Permitted")
    (#x84 "C84")
    (#x85 "Next-Line")
    (#x86 "Start-Selected-Area")
    (#x87 "End-Selected-Area")
    (#x88 "Character-Tabulation-Set")
    (#x89 "Character-Tabulation-With-Justification")
    (#x8A "Line-Tabulation-Set")
    (#x8B "Partial-Line-Forward")
    (#x8C "Partial-Line-Backward")
    (#x8D "Reverse-Linefeed")
    (#x8E "Single-Shift-Two")
    (#x8F "Single-Shift-Three")
    (#x90 "Device-Control-String")
    (#x91 "Private-Use-One")
    (#x92 "Private-Use-Two")
    (#x93 "Set-Transmit-State")
    (#x94 "Cancel-Character")
    (#x95 "Message-Waiting")
    (#x96 "Start-Guarded-Area")
    (#x97 "End-Guarded-Area")
    (#x98 "Start-String")
    (#x99 "C99")
    (#x9A "Single-Character-Introducer")
    (#x9B "Control-Sequence-Introducer")
    (#x9C "String-Terminator")
    (#x9D "Operating-System-Command")
    (#x9E "Privacy-Message")
    (#x9F "Application-Program-Command"))) ; *** See Note above

;;;; UCD accessor functions

;;; The first (* 8 396) => 3168 entries in **CHARACTER-DATABASE**
;;; contain entries for the distinct character attributes:
;;; specifically, indexes into the GC kinds, Bidi kinds, CCC kinds,
;;; the decimal digit property, the digit property and the
;;; bidi-mirrored boolean property.  (There are two spare bytes for
;;; other information, should that become necessary)
;;;
;;; the next (ash #x110000 -8) entries contain single-byte indexes
;;; into a table of 256-element 4-byte-sized entries.  These entries
;;; follow directly on, and are of the form
;;; {attribute-index[11b],transformed-code-point[21b]}x256, where the
;;; attribute index is an index into the miscellaneous information
;;; table, and the transformed code point is the code point of the
;;; simple mapping of the character to its lowercase or uppercase
;;; equivalent, as appropriate and if any.
;;;
;;; I feel the opacity of the above suggests the need for a diagram:
;;;
;;;         C  _______________________________________
;;;           /                                       \
;;;          L                                         \
;;;  [***************|=============================|--------...]
;;;                 (a)      \                       _
;;;                         A \______________________/| B
;;;
;;; To look up information about a character, take the high 13 bits of
;;; its code point, and index the character database with that and a
;;; base of 3168 (going past the miscellaneous information[*], so
;;; treating (a) as the start of the array).  This, labelled A, gives
;;; us another index into the detailed pages[-], which we can use to
;;; look up the details for the character in question: we add the low
;;; 8 bits of the character, shifted twice (because we have four-byte
;;; table entries) to 1024 times the `page' index, with a base of 7520
;;; to skip over everything else.  This gets us to point B.  If we're
;;; after a transformed code point (i.e. an upcase or downcase
;;; operation), we can simply read it off now, beginning with an
;;; offset of 11 bits from point B in some endianness; if we're
;;; looking for miscellaneous information, we take the 11-bit value at
;;; B, and index the character database once more to get to the
;;; relevant miscellaneous information.
;;;
;;; As an optimization to the common case (pun intended) of looking up
;;; case information for a character, the entries in C above are
;;; sorted such that the characters which are UPPER-CASE-P in CL terms
;;; have index values lower than all others, followed by those which
;;; are LOWER-CASE-P in CL terms; this permits implementation of
;;; character case tests without actually going to the trouble of
;;; looking up the value associated with the index.  (Actually, this
;;; isn't just a speed optimization; the information about whether a
;;; character is BOTH-CASE-P is used just in the ordering and not
;;; explicitly recorded in the database).
;;;
;;; The moral of all this?  Next time, don't just say "FIXME: document
;;; this"
(defun ucd-index (char)
  (let* ((cp (char-code char))
         (cp-high (ash cp -8))
         (page (aref **character-database** (+ 3168 cp-high))))
    (+ 7520 (ash page 10) (ash (ldb (byte 8 0) cp) 2))))

(declaim (ftype (sfunction (t) (unsigned-byte 11)) ucd-value-0))
(defun ucd-value-0 (char)
  (let ((index (ucd-index char))
        (character-database **character-database**))
    (dpb (aref character-database index)
         (byte 8 3)
         (ldb (byte 3 5) (aref character-database (+ index 1))))))

(declaim (ftype (sfunction (t) (unsigned-byte 21)) ucd-value-1))
(defun ucd-value-1 (char)
  (let ((index (ucd-index char))
        (character-database **character-database**))
    (dpb (aref character-database (+ index 1))
         (byte 5 16)
         (dpb (aref character-database (+ index 2))
              (byte 8 8)
              (aref character-database (+ index 3))))))

(declaim (ftype (sfunction (t) (unsigned-byte 8)) ucd-general-category))
(defun ucd-general-category (char)
  (aref **character-database** (* 8 (ucd-value-0 char))))

(defun ucd-decimal-digit (char)
  (let ((decimal-digit (aref **character-database**
                             (+ 3 (* 8 (ucd-value-0 char))))))
    (when (< decimal-digit 10)
      decimal-digit)))
(declaim (ftype (sfunction (t) (unsigned-byte 8)) ucd-ccc))
(defun ucd-ccc (char)
  (aref **character-database** (+ 2 (* 8 (ucd-value-0 char)))))

(defun char-code (char)
  #!+sb-doc
  "Return the integer code of CHAR."
  (char-code char))

(defun char-int (char)
  #!+sb-doc
  "Return the integer code of CHAR. (In SBCL this is the same as CHAR-CODE, as
there are no character bits or fonts.)"
  (char-code char))

(defun code-char (code)
  #!+sb-doc
  "Return the character with the code CODE."
  (code-char code))

(defun character (object)
  #!+sb-doc
  "Coerce OBJECT into a CHARACTER if possible. Legal inputs are characters,
strings and symbols of length 1."
  (flet ((do-error (control args)
           (error 'simple-type-error
                  :datum object
                  ;;?? how to express "symbol with name of length 1"?
                  :expected-type '(or character (string 1))
                  :format-control control
                  :format-arguments args)))
    (typecase object
      (character object)
      (string (if (= 1 (length (the string object)))
                  (char object 0)
                  (do-error
                   "String is not of length one: ~S" (list object))))
      (symbol (if (= 1 (length (symbol-name object)))
                  (schar (symbol-name object) 0)
                  (do-error
                   "Symbol name is not of length one: ~S" (list object))))
      (t (do-error "~S cannot be coerced to a character." (list object))))))

(defun char-name (char)
  #!+sb-doc
  "Return the name (a STRING) for a CHARACTER object."
  (let ((char-code (char-code char)))
    (or (second (assoc char-code *base-char-name-alist*))
        #!+sb-unicode
        (let ((h-code (cdr (binary-search char-code
                                          (car *unicode-character-name-database*)
                                          :key #'car))))
          (cond
            (h-code
             (huffman-decode h-code *unicode-character-name-huffman-tree*))
            ((< char-code #x10000)
             (format nil "U~4,'0X" char-code))
            (t
             (format nil "U~8,'0X" char-code)))))))

(defun name-char (name)
  #!+sb-doc
  "Given an argument acceptable to STRING, NAME-CHAR returns a character whose
name is that string, if one exists. Otherwise, NIL is returned."
  (or (let ((char-code (car (rassoc-if (lambda (names)
                                         (member name names :test #'string-equal))
                                       *base-char-name-alist*))))
        (when char-code
          (code-char char-code)))
      #!+sb-unicode
      (let ((encoding (huffman-encode (string-upcase name)
                                       *unicode-character-name-huffman-tree*)))
        (when encoding
          (let* ((char-code
                  (car (binary-search encoding
                                      (cdr *unicode-character-name-database*)
                                      :key #'cdr)))
                 (name-string (string name))
                 (name-length (length name-string)))
            (cond
              (char-code
               (code-char char-code))
              ((and (or (= name-length 9)
                        (= name-length 5))
                    (char-equal (char name-string 0) #\U)
                    (loop for i from 1 below name-length
                          always (digit-char-p (char name-string i) 16)))
               (code-char (parse-integer name-string :start 1 :radix 16)))
              (t
               nil)))))))

;;;; predicates

(defun standard-char-p (char)
  #!+sb-doc
  "The argument must be a character object. STANDARD-CHAR-P returns T if the
argument is a standard character -- one of the 95 ASCII printing characters or
<return>."
  (and (typep char 'base-char)
       (let ((n (char-code (the base-char char))))
         (or (< 31 n 127)
             (= n 10)))))

(defun %standard-char-p (thing)
  #!+sb-doc
  "Return T if and only if THING is a standard-char. Differs from
STANDARD-CHAR-P in that THING doesn't have to be a character."
  (and (characterp thing) (standard-char-p thing)))

(defun graphic-char-p (char)
  #!+sb-doc
  "The argument must be a character object. GRAPHIC-CHAR-P returns T if the
argument is a printing character (space through ~ in ASCII), otherwise returns
NIL."
  (let ((n (char-code char)))
    (or (< 31 n 127)
        (< 159 n))))

(defun alpha-char-p (char)
  #!+sb-doc
  "The argument must be a character object. ALPHA-CHAR-P returns T if the
argument is an alphabetic character, A-Z or a-z; otherwise NIL."
  (< (ucd-general-category char) 5))

(defun upper-case-p (char)
  #!+sb-doc
  "The argument must be a character object; UPPER-CASE-P returns T if the
argument is an upper-case character, NIL otherwise."
  (< (ucd-value-0 char) 4))

(defun lower-case-p (char)
  #!+sb-doc
  "The argument must be a character object; LOWER-CASE-P returns T if the
argument is a lower-case character, NIL otherwise."
  (< 3 (ucd-value-0 char) 8))

(defun both-case-p (char)
  #!+sb-doc
  "The argument must be a character object. BOTH-CASE-P returns T if the
argument is an alphabetic character and if the character exists in both upper
and lower case. For ASCII, this is the same as ALPHA-CHAR-P."
  (< (ucd-value-0 char) 8))

(defun digit-char-p (char &optional (radix 10.))
  #!+sb-doc
  "If char is a digit in the specified radix, returns the fixnum for which
that digit stands, else returns NIL."
  (let ((m (- (char-code char) 48)))
    (declare (fixnum m))
    (cond ((<= radix 10.)
           ;; Special-case decimal and smaller radices.
           (if (and (>= m 0) (< m radix))  m  nil))
          ;; Digits 0 - 9 are used as is, since radix is larger.
          ((and (>= m 0) (< m 10)) m)
          ;; Check for upper case A - Z.
          ((and (>= (setq m (- m 7)) 10) (< m radix)) m)
          ;; Also check lower case a - z.
          ((and (>= (setq m (- m 32)) 10) (< m radix)) m)
          ;; Else, fail.
          (t (let ((number (ucd-decimal-digit char)))
               (when (and number (< number radix))
                 number))))))

(defun alphanumericp (char)
  #!+sb-doc
  "Given a character-object argument, ALPHANUMERICP returns T if the argument
is either numeric or alphabetic."
  (let ((gc (ucd-general-category char)))
    (or (< gc 5)
        (= gc 12))))

(defun char= (character &rest more-characters)
  #!+sb-doc
  "Return T if all of the arguments are the same character."
  (declare (truly-dynamic-extent more-characters))
  (dolist (c more-characters t)
    (declare (type character c))
    (unless (eq c character) (return nil))))

(defun char/= (character &rest more-characters)
  #!+sb-doc
  "Return T if no two of the arguments are the same character."
  (declare (truly-dynamic-extent more-characters))
  (do* ((head character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (declare (type character head))
    (dolist (c list)
      (declare (type character c))
      (when (eq head c) (return-from char/= nil)))))

(defun char< (character &rest more-characters)
  #!+sb-doc
  "Return T if the arguments are in strictly increasing alphabetic order."
  (declare (truly-dynamic-extent more-characters))
  (do* ((c character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (unless (< (char-int c)
               (char-int (car list)))
      (return nil))))

(defun char> (character &rest more-characters)
  #!+sb-doc
  "Return T if the arguments are in strictly decreasing alphabetic order."
  (declare (truly-dynamic-extent more-characters))
  (do* ((c character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (unless (> (char-int c)
               (char-int (car list)))
      (return nil))))

(defun char<= (character &rest more-characters)
  #!+sb-doc
  "Return T if the arguments are in strictly non-decreasing alphabetic order."
  (declare (truly-dynamic-extent more-characters))
  (do* ((c character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (unless (<= (char-int c)
                (char-int (car list)))
      (return nil))))

(defun char>= (character &rest more-characters)
  #!+sb-doc
  "Return T if the arguments are in strictly non-increasing alphabetic order."
  (declare (truly-dynamic-extent more-characters))
  (do* ((c character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (unless (>= (char-int c)
                (char-int (car list)))
      (return nil))))

;;; EQUAL-CHAR-CODE is used by the following functions as a version of CHAR-INT
;;;  which loses font, bits, and case info.

(defmacro equal-char-code (character)
  (let ((ch (gensym)))
    `(let ((,ch ,character))
      (if (= (ucd-value-0 ,ch) 0)
          (ucd-value-1 ,ch)
          (char-code ,ch)))))

(defun two-arg-char-equal (c1 c2)
  (= (equal-char-code c1) (equal-char-code c2)))

(defun char-equal (character &rest more-characters)
  #!+sb-doc
  "Return T if all of the arguments are the same character.
Case is ignored."
  (declare (truly-dynamic-extent more-characters))
  (do ((clist more-characters (cdr clist)))
      ((null clist) t)
    (unless (two-arg-char-equal (car clist) character)
      (return nil))))

(defun two-arg-char-not-equal (c1 c2)
  (/= (equal-char-code c1) (equal-char-code c2)))

(defun char-not-equal (character &rest more-characters)
  #!+sb-doc
  "Return T if no two of the arguments are the same character.
Case is ignored."
  (declare (truly-dynamic-extent more-characters))
  (do* ((head character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (unless (do* ((l list (cdr l)))
                 ((null l) t)
              (if (two-arg-char-equal head (car l))
                  (return nil)))
      (return nil))))

(defun two-arg-char-lessp (c1 c2)
  (< (equal-char-code c1) (equal-char-code c2)))

(defun char-lessp (character &rest more-characters)
  #!+sb-doc
  "Return T if the arguments are in strictly increasing alphabetic order.
Case is ignored."
  (declare (truly-dynamic-extent more-characters))
  (do* ((c character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (unless (two-arg-char-lessp c (car list))
      (return nil))))

(defun two-arg-char-greaterp (c1 c2)
  (> (equal-char-code c1) (equal-char-code c2)))

(defun char-greaterp (character &rest more-characters)
  #!+sb-doc
  "Return T if the arguments are in strictly decreasing alphabetic order.
Case is ignored."
  (declare (truly-dynamic-extent more-characters))
  (do* ((c character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (unless (two-arg-char-greaterp c (car list))
      (return nil))))

(defun two-arg-char-not-greaterp (c1 c2)
  (<= (equal-char-code c1) (equal-char-code c2)))

(defun char-not-greaterp (character &rest more-characters)
  #!+sb-doc
  "Return T if the arguments are in strictly non-decreasing alphabetic order.
Case is ignored."
  (declare (truly-dynamic-extent more-characters))
  (do* ((c character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (unless (two-arg-char-not-greaterp c (car list))
      (return nil))))

(defun two-arg-char-not-lessp (c1 c2)
  (>= (equal-char-code c1) (equal-char-code c2)))

(defun char-not-lessp (character &rest more-characters)
  #!+sb-doc
  "Return T if the arguments are in strictly non-increasing alphabetic order.
Case is ignored."
  (declare (truly-dynamic-extent more-characters))
  (do* ((c character (car list))
        (list more-characters (cdr list)))
       ((null list) t)
    (unless (two-arg-char-not-lessp c (car list))
      (return nil))))

;;;; miscellaneous functions

(defun char-upcase (char)
  #!+sb-doc
  "Return CHAR converted to upper-case if that is possible. Don't convert
lowercase eszet (U+DF)."
  (if (< 3 (ucd-value-0 char) 8)
      (code-char (ucd-value-1 char))
      char))

(defun char-downcase (char)
  #!+sb-doc
  "Return CHAR converted to lower-case if that is possible."
  (if (< (ucd-value-0 char) 4)
      (code-char (ucd-value-1 char))
      char))

(defun digit-char (weight &optional (radix 10))
  #!+sb-doc
  "All arguments must be integers. Returns a character object that represents
a digit of the given weight in the specified radix. Returns NIL if no such
character exists."
  (and (typep weight 'fixnum)
       (>= weight 0) (< weight radix) (< weight 36)
       (code-char (if (< weight 10) (+ 48 weight) (+ 55 weight)))))

(defun char-decomposition-info (char)
  (aref **character-database** (+ 6 (* 8 (ucd-value-0 char)))))

(defun char-decomposition (char)
  (let* ((cp (char-code char))
         (cp-high (ash cp -8))
         (decompositions **character-decompositions**)
         (long-decompositions **character-long-decompositions**)
         (index (+ #x1100
                   (ash (aref decompositions cp-high) 10)
                   (ash (ldb (byte 8 0) cp) 2)))
         (v0 (aref decompositions index))
         (v1 (aref decompositions (+ index 1)))
         (v2 (aref decompositions (+ index 2)))
         (v3 (aref decompositions (+ index 3)))
         (length (dpb v0 (byte 8 3) (ldb (byte 3 5) v1)))
         (entry (dpb (ldb (byte 5 0) v1) (byte 5 16)
                     (dpb v2 (byte 8 8) v3))))
    (if (= length 1)
        (string (code-char entry))
        (if (<= #xac00 cp #xd7a3)
            ;; see Unicode 6.2, section 3-12
            (let* ((sbase #xac00)
                   (lbase #x1100)
                   (vbase #x1161)
                   (tbase #x11a7)
                   (lcount 19)
                   (vcount 21)
                   (tcount 28)
                   (ncount (* vcount tcount))
                   (scount (* lcount ncount))
                   (sindex (- cp sbase))
                   (lindex (floor sindex ncount))
                   (vindex (floor (mod sindex ncount) tcount))
                   (tindex (mod sindex tcount))
                   (result (make-string length)))
              (declare (ignore scount))
              (setf (char result 0) (code-char (+ lbase lindex)))
              (setf (char result 1) (code-char (+ vbase vindex)))
              (when (> tindex 0)
                (setf (char result 2) (code-char (+ tbase tindex))))
              result)
            (let ((result (make-string length))
                  (e (* 4 entry)))
              (dotimes (i length result)
                (let ((code (dpb (aref long-decompositions (+ e 1))
                                 (byte 8 16)
                                 (dpb (aref long-decompositions (+ e 2))
                                      (byte 8 8)
                                      (aref long-decompositions (+ e 3))))))
                  (setf (char result i) (code-char code)))
                (incf e 4)))))))

(defun decompose-char (char)
  (if (= (char-decomposition-info char) 0)
      (string char)
      (char-decomposition char)))

(defun decompose-string (string &optional (kind :canonical))
  (declare (type (member :canonical :compatibility) kind))
  (flet ((canonical (char)
           (= 1 (char-decomposition-info char)))
         (compat (char)
           (/= 0 (char-decomposition-info char))))
    (let (result
          (fun (ecase kind
                 (:canonical #'canonical)
                 (:compatibility #'compat))))
      (do* ((start 0 (1+ end))
            (end (position-if fun string :start start)
                 (position-if fun string :start start)))
           ((null end) (push (subseq string start end) result))
        (unless (= start end)
          (push (subseq string start end) result))
        ;; FIXME: this recursive call to DECOMPOSE-STRING is necessary
        ;; for correctness given our direct encoding of the
        ;; decomposition data in UnicodeData.txt.  It would, however,
        ;; be straightforward enough to perform the recursion in table
        ;; construction, and then have this simply revert to a single
        ;; lookup.  (Wait for tests to be hooked in, then implement).
        (push (decompose-string (decompose-char (char string end)) kind)
              result))
      (apply 'concatenate 'string (nreverse result)))))

(defun sort-combiners (string)
  (let (result (start 0) first-cc first-non-cc)
    (tagbody
     again
       (setf first-cc (position 0 string :key #'ucd-ccc :test #'/= :start start))
       (when first-cc
         (setf first-non-cc (position 0 string :key #'ucd-ccc :test #'= :start first-cc)))
       (push (subseq string start first-cc) result)
       (when first-cc
         (push (stable-sort (subseq string first-cc first-non-cc) #'< :key #'ucd-ccc) result))
       (when first-non-cc
         (setf start first-non-cc first-cc nil first-non-cc nil)
         (go again)))
    (apply 'concatenate 'string (nreverse result))))

(defun primary-composition (char1 char2)
  (let ((c1 (char-code char1))
        (c2 (char-code char2)))
    (cond
      ((gethash (dpb (char-code char1) (byte 21 21) (char-code char2))
                **character-primary-compositions**))
      ((and (<= #x1100 c1) (<= c1 #x1112)
            (<= #x1161 c2) (<= c2 #x1175))
       (let ((lindex (- c1 #x1100))
             (vindex (- c2 #x1161)))
         (code-char (+ #xac00 (* lindex 588) (* vindex 28)))))
      ((and (<= #xac00 c1) (<= c1 #.(+ #xac00 11171))
            (<= #x11a8 c2) (<= c2 #x11c2)
            (= 0 (rem (- c1 #xac00) 28)))
       (code-char (+ c1 (- c2 #x11a7)))))))

;;; This implements a sequence data structure, specialized for
;;; efficient deletion of characters at an index, along with tolerable
;;; random access.  The purpose is to support the canonical
;;; composition algorithm from Unicode, which involves replacing (not
;;; necessarily consecutive) pairs of code points with a single code
;;; point (e.g. [#\e #\combining_acute_accent] with
;;; #\latin_small_letter_e_with_acute).  The data structure is a list
;;; of three-element lists, each denoting a chunk of string data
;;; starting at the first index and ending at the second.
;;;
;;; Actually, the implementation isn't particularly efficient, and
;;; would probably benefit from being rewritten in terms of displaced
;;; arrays, which would substantially reduce copying.
;;;
;;; (also, generic sequences.  *sigh*.)
(defun lref (lstring index)
  (dolist (l lstring)
    (when (and (<= (first l) index)
               (< index (second l)))
      (return (aref (third l) (- index (first l)))))))
(defun (setf lref) (newchar lstring index)
  (dolist (l lstring)
    (when (and (<= (first l) index)
               (< index (second l)))
      (return (setf (aref (third l) (- index (first l))) newchar)))))
(defun llength (lstring)
  (second (first (last lstring))))
(defun lstring (lstring)
  (let ((result (make-string (llength lstring))))
    (dolist (l lstring result)
      (replace result (third l) :start1 (first l) :end1 (second l)))))
(defun ldelete (lstring index)
  (do* ((ls lstring (cdr ls))
        (l (car ls) (car ls))
        so-fars)
       ((and (<= (first l) index)
             (< index (second l)))
        (append
         (nreverse so-fars)
         (cond
           ((= (first l) index)
            (list (list (first l) (1- (second l)) (subseq (third l) 1))))
           ((= index (1- (second l)))
            (list (list (first l) (1- (second l)) (subseq (third l) 0 (1- (length (third l)))))))
           (t
            (list
             (list (first l) index
                   (subseq (third l) 0 (- index (first l))))
             (list index (1- (second l))
                   (subseq (third l) (1+ (- index (first l))))))))
         (mapcar (lambda (x) (list (1- (first x)) (1- (second x)) (third x)))
                 (cdr ls))))
    (push l so-fars)))

(defun canonically-compose (string)
  (labels ()
    (let* ((result (list (list 0 (length string) string)))
           (previous-starter-index (position 0 string :key #'ucd-ccc))
           (i (and previous-starter-index (1+ previous-starter-index))))
      (when (or (not i) (= i (length string)))
        (return-from canonically-compose string))
      (tagbody
       again
         (when (and (>= (- i previous-starter-index) 2)
                    ;; test for Blocked (Unicode 3.11 para. D115)
                    ;;
                    ;; (assumes here that string has sorted combiners,
                    ;; so can look back just one step)
                    (>= (ucd-ccc (lref result (1- i)))
                        (ucd-ccc (lref result i))))
           (when (= (ucd-ccc (lref result i)) 0)
             (setf previous-starter-index i))
           (incf i)
           (go next))

         (let ((comp (primary-composition (lref result previous-starter-index)
                                          (lref result i))))
           (cond
             (comp
              (setf (lref result previous-starter-index) comp)
              (setf result (ldelete result i)))
             (t
              (when (= (ucd-ccc (lref result i)) 0)
                (setf previous-starter-index i))
              (incf i))))
       next
         (unless (= i (llength result))
           (go again)))
      (if (= i (length string))
          string
          (lstring result)))))

(defun normalize-string (string &optional (form :nfd))
  (declare (type (member :nfd :nfkd :nfc :nfkc) form))
  (etypecase string
    #!+sb-unicode
    (base-string string)
    ((or (array character (*)) #!-sb-unicode base-string)
     (ecase form
       ((:nfc)
        (canonically-compose (sort-combiners (decompose-string string))))
       ((:nfd)
        (sort-combiners (decompose-string string)))
       ((:nfkc)
        (canonically-compose (sort-combiners (decompose-string string :compatibility))))
       ((:nfkd)
        (sort-combiners (decompose-string string :compatibility)))))
    ((array nil (*)) string)))
