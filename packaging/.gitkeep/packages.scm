;;; GNU Guix package definition for feedback-a-tron
;;; 
;;; To use as a channel, add to ~/.config/guix/channels.scm:
;;;
;;; (cons* (channel
;;;         (name 'feedback-a-tron)
;;;         (url "https://github.com/hyperpolymath/feedback-a-tron")
;;;         (branch "main")
;;;         (introduction
;;;          (make-channel-introduction
;;;           "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
;;;           (openpgp-fingerprint
;;;            "XXXX XXXX XXXX XXXX XXXX  XXXX XXXX XXXX XXXX XXXX"))))
;;;        %default-channels)

(define-module (feedback-a-tron packages)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system mix)
  #:use-module (guix build-system julia)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages erlang)
  #:use-module (gnu packages julia)
  #:use-module (gnu packages version-control))

(define-public feedback-a-tron-mcp
  (package
    (name "feedback-a-tron-mcp")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/hyperpolymath/feedback-a-tron")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system mix-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'chdir
           (lambda _
             (chdir "elixir-mcp"))))))
    (inputs
     (list erlang))
    (synopsis "GitHub management MCP server with Datalog analysis")
    (description
     "An MCP (Model Context Protocol) server for GitHub repository management.
Features include:
@itemize
@item Issue creation with templates
@item Datalog-based issue analysis
@item Related issue detection
@item Regression tracking
@item Component hotspot analysis
@end itemize")
    (home-page "https://github.com/hyperpolymath/feedback-a-tron")
    (license license:asl2.0)))

(define-public feedback-a-tron-stats
  (package
    (name "feedback-a-tron-stats")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/hyperpolymath/feedback-a-tron")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system julia-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (add-after 'unpack 'chdir
           (lambda _
             (chdir "julia-stats"))))))
    (inputs
     (list julia))
    (synopsis "GitHub activity statistics in Julia")
    (description
     "Personal GitHub activity statistics and analysis.
Track your issues, PRs, comments, contributions, and watched repos.")
    (home-page "https://github.com/hyperpolymath/feedback-a-tron")
    (license license:asl2.0)))

;; Meta-package that includes everything
(define-public feedback-a-tron
  (package
    (name "feedback-a-tron")
    (version "0.1.0")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     '(#:builder (begin
                   (mkdir %output)
                   #t)))
    (propagated-inputs
     (list feedback-a-tron-mcp
           feedback-a-tron-stats))
    (synopsis "Complete feedback-a-tron suite")
    (description "Meta-package installing all feedback-a-tron components.")
    (home-page "https://github.com/hyperpolymath/feedback-a-tron")
    (license license:asl2.0)))
