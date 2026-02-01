;; SPDX-License-Identifier: PMPL-1.0-or-later
;; NEUROSYM.scm - Neurosymbolic config

(define neurosym-config
  `((version . "1.0.1")
    (updated . "2026-01-27")
    (symbolic-layer
      ((type . "scheme")
       (reasoning . "deductive")))
    (neural-layer
      ((embeddings . false)
       (fine-tuning . false)))
    (integration . ())))
