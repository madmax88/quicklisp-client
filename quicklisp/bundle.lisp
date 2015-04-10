;;;; bundle.lisp

(in-package #:ql-bundle)

;;; Bundling is taking a set of Quicklisp-provided systems and
;;; creating a directory structure and metadata in which those systems
;;; can be loaded without involving Quicklisp.
;;;
;;; This works only for systems that are directly provided by
;;; Quicklisp. It can't reach out into ASDF-land and copy sources
;;; around.

(defgeneric find-system (system bundle))
(defgeneric add-system (system bundle))
(defgeneric ensure-system (system bundle))

(defgeneric find-release (relase bundle))
(defgeneric add-release (release bundle))
(defgeneric ensure-release (release bundle))

(defgeneric write-loader-script (bundle stream))
(defgeneric write-system-index (bundle stream))
(defgeneric write-bundle (bundle target))

(defgeneric unpack-release (release target))
(defgeneric unpack-releases (bundle target))

(defgeneric write-bundle (bundle target))


;;; Implementation

;;; Conditions

(define-condition object-not-found (error)
  ((name
    :initarg :name
    :reader object-not-found-name)
   (type
    :initarg :type
    :reader object-not-found-type))
  (:report
   (lambda (condition stream)
     (format stream "~A ~S not found"
             (object-not-found-type condition)
             (object-not-found-name condition))))
  (:default-initargs
   :type "Object"))

(define-condition system-not-found (object-not-found)
  ()
  (:default-initargs
   :type "System"))

(define-condition release-not-found (object-not-found)
  ()
  (:default-initargs
   :type "Release"))


(defclass bundle ()
  ((release-table
    :initarg :release-table
    :reader release-table)
   (system-table
    :initarg :system-table
    :reader system-table))
  (:default-initargs
   :release-table (make-hash-table :test 'equalp)
   :system-table (make-hash-table :test 'equalp)))

(defmethod print-object ((bundle bundle) stream)
  (print-unreadable-object (bundle stream :type t)
    (format stream "~D release~:P, ~D system~:P"
            (hash-table-count (release-table bundle))
            (hash-table-count (system-table bundle)))))

(defmethod provided-releases ((bundle bundle))
  (let ((releases '()))
    (maphash (lambda (name release)
               (declare (ignore name))
               (push release releases))
             (release-table bundle))
    (sort releases 'string< :key 'name)))

(defmethod provided-systems ((bundle bundle))
  (sort (mapcan #'provided-systems (provided-releases bundle))
        'string<
        :key 'name))

(defmethod find-system (name (bundle bundle))
  (values (gethash name (system-table bundle))))

(defmethod add-system (name (bundle bundle))
  (let ((system (ql-dist:find-system name)))
    (unless system
      (error 'system-not-found
             :name name))
    (ensure-release (name (release system)) bundle)
    system))

(defmethod ensure-system (name (bundle bundle))
  (or (find-system name bundle)
      (add-system name bundle)))

(defmethod find-release (name (bundle bundle))
  (values (gethash name (release-table bundle))))

(defmethod add-release (name (bundle bundle))
  (let ((release (ql-dist:find-release name)))
    (unless release
      (error 'release-not-found
             :name name))
    (setf (gethash (name release) (release-table bundle)) release)
    (let ((system-table (system-table bundle)))
      (dolist (system (provided-systems release))
        (setf (gethash (name system) system-table) system)))
    release))

(defmethod ensure-release (name (bundle bundle))
  (or (find-release name bundle)
      (add-release name bundle)))


(defun add-systems-recursively (names bundle)
  (with-consistent-dists
    (labels ((add-one (name)
               (let ((system (ensure-system name bundle)))
                 (dolist (required-system-name (required-systems system))
                   (add-one required-system-name)))))
      (map nil #'add-one names)))
  bundle)


(defmethod unpack-release (release target)
  (let ((*default-pathname-defaults* (pathname
                                      (ensure-directories-exist target)))
        (archive (ensure-local-archive-file release))
        (temp-tar (ensure-directories-exist
                   (ql-setup:qmerge "tmp/bundle.tar"))))
    (ql-gunzipper:gunzip archive temp-tar)
    (ql-minitar:unpack-tarball temp-tar :directory "software/")
    (delete-file temp-tar)
    release))

(defmethod unpack-releases ((bundle bundle) target)
  (dolist (release (provided-releases bundle))
    (unpack-release release target))
  bundle)

(defmethod write-system-index ((bundle bundle) stream)
  (dolist (release (provided-releases bundle))
    ;; Working with strings, here, intentionally not with pathnames
    (let ((prefix (concatenate 'string "software/" (prefix release))))
      (dolist (system-file (system-files release))
        (format stream "~A/~A~%" prefix system-file)))))

(defmethod write-loader-script ((bundle bundle) stream)
  (write-line ";;;; TBD" stream))

(defmethod write-bundle ((bundle bundle) target)
  (unpack-releases bundle target)
  (let ((index-file (merge-pathnames "system-index.txt" target))
        (loader-file (merge-pathnames "bundle-loader.lisp" target)))
    (with-open-file (stream index-file :direction :output
                            :if-exists :supersede)
      (write-system-index bundle stream))
    (with-open-file (stream loader-file :direction :output
                            :if-exists :supersede)
      (write-loader-script bundle stream)))
  bundle)