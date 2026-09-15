;; SPDX-License-Identifier: MPL-2.0
;; Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
;;
;; Guix development environment for feedback-o-tron.
;; Usage: guix shell -D -f guix.scm

(use-modules (guix packages)
             (guix build-system gnu)
             (guix licenses)
             (gnu packages base)
             (gnu packages bash)
             (gnu packages erlang)
             (gnu packages elixir)
             (gnu packages version-control))

(package
  (name "feedback-o-tron")
  (version "1.0.0")
  (source #f)
  (build-system gnu-build-system)
  (inputs (list coreutils bash git erlang elixir))
  (synopsis "Feedback and bug-report submission for people and AI agents")
  (description
   "Feedback-o-Tron submits feedback and bug reports to GitHub, GitLab, email
and NNTP, from a command line, from an MCP host, or over a loopback HTTP
intake.  Nothing leaves the machine until a person has seen the whole payload
and said yes.")
  (home-page "https://github.com/hyperpolymath/feedback-o-tron")
  (license mpl2.0))
