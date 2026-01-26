;; SPDX-License-Identifier: PMPL-1.0-or-later
;; ECOSYSTEM.scm - Ecosystem positioning

(ecosystem
  ((version . "1.0.0")
   (name . "feedback-o-tron")
   (type . "application")
   (purpose . "Hyperpolymath project")
   (position-in-ecosystem . "supporting")
   (related-projects
     ((palimpsest-license . "license-framework")))
   (what-this-is . ("Hyperpolymath project"))
   (what-this-is-not . ()))
  (opsm-integration
    (relationship "core")
    (description "feedback/telemetry capture for OPSM (opt‑in).")
    (direction "opsm -> feedback-o-tron"))
)
