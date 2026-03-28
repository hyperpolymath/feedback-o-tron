; SPDX-License-Identifier: PMPL-1.0-or-later
;; guix.scm — GNU Guix package definition for feedback-o-tron
;; Usage: guix shell -f guix.scm

(use-modules (guix packages)
             (guix build-system gnu)
             (guix licenses))

(package
  (name "feedback-o-tron")
  (version "0.1.0")
  (source #f)
  (build-system gnu-build-system)
  (synopsis "feedback-o-tron")
  (description "feedback-o-tron — part of the hyperpolymath ecosystem.")
  (home-page "https://github.com/hyperpolymath/feedback-o-tron")
  (license ((@@ (guix licenses) license) "PMPL-1.0-or-later"
             "https://github.com/hyperpolymath/palimpsest-license")))
