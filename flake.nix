{
  description = "GitHub repository management with Datalog analysis";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Elixir MCP server
        elixirMcp = pkgs.beamPackages.mixRelease {
          pname = "feedback-a-tron-mcp";
          version = "0.1.0";
          src = ./elixir-mcp;
          
          mixNixDeps = import ./elixir-mcp/mix.nix { inherit pkgs; };
          
          meta = with pkgs.lib; {
            description = "GitHub management MCP server with Datalog analysis";
            homepage = "https://github.com/hyperpolymath/feedback-a-tron";
            license = licenses.asl20;
            platforms = platforms.unix;
          };
        };

        # Julia stats package
        juliaStats = pkgs.stdenv.mkDerivation {
          pname = "feedback-a-tron-stats";
          version = "0.1.0";
          src = ./julia-stats;
          
          nativeBuildInputs = [ pkgs.julia ];
          
          installPhase = ''
            mkdir -p $out/share/julia/packages/FeedbackStats
            cp -r * $out/share/julia/packages/FeedbackStats/
          '';
          
          meta = with pkgs.lib; {
            description = "GitHub activity statistics in Julia";
            homepage = "https://github.com/hyperpolymath/feedback-a-tron";
            license = licenses.asl20;
          };
        };

        # Scraper script
        scraper = pkgs.writeScriptBin "feedback-scraper" ''
          #!${pkgs.elixir}/bin/elixir
          ${builtins.readFile ./scripts/scraper.exs}
        '';

      in {
        packages = {
          mcp = elixirMcp;
          stats = juliaStats;
          scraper = scraper;
          default = elixirMcp;
        };

        apps = {
          mcp = flake-utils.lib.mkApp {
            drv = elixirMcp;
            exePath = "/bin/gh_manage";
          };
          scraper = flake-utils.lib.mkApp {
            drv = scraper;
          };
          default = self.apps.${system}.mcp;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Elixir development
            elixir
            erlang
            
            # Julia development
            julia
            
            # Nickel for config
            nickel
            
            # Tools
            git
            gh  # GitHub CLI
            
            # Optional: Ada/SPARK (if building ada-core)
            # gnat
            # gprbuild
            
            # Optional: ReScript (if building UI)
            # nodePackages.rescript
            
            # Optional: Oxigraph
            # oxigraph
          ];
          
          shellHook = ''
            echo "feedback-a-tron development shell"
            echo ""
            echo "Available commands:"
            echo "  cd elixir-mcp && mix deps.get && mix compile"
            echo "  cd julia-stats && julia --project=. -e 'using Pkg; Pkg.instantiate()'"
            echo "  ./scripts/scraper.exs --help"
            echo ""
          '';
        };
      }
    );
}
