{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    systems = [
      "aarch64-linux"
      "aarch64-darwin"
      "x86_64-linux"
      "x86_64-darwin"
    ];
    perSystem = f:
      nixpkgs.lib.genAttrs systems (system:
        f rec {
          inherit system;
          pkgs = nixpkgs.legacyPackages.${system};
          lib = pkgs.lib;
          pkgs' = self.packages.${system};
        });
  in {
    packages = perSystem ({pkgs, ...}: {
      bootstrap = with pkgs; let
        catalog = fetchurl {
          url = "https://pkgs.racket-lang.org/pkgs-all?version=${racket.version}";
          hash = "sha256-dJ5E9wCr5RZcJyDJBQEmvgDKjTR20c1XapDNoPQKxAM=";
        };
      in
        runCommand "racket-pkgs" {
          nativeBuildInputs = [racket cacert nix];
          outputHash = "sha256-XpbQ6xJIlaE7wGQfahSVwHci2dlMFPeCWVzBdI0rOA8=";
          outputHashMode = "recursive";
        } ''
          echo Setting up racket
          export HOME=$(mktemp -d)
          # raco pkg install --auto graph threading
          raco pkg install \
              --user \
              --copy \
              --batch \
              --no-cache \
              -j $NIX_BUILD_CORES \
              --deps search-auto \
              -D graph threading
          echo Generating Racket package catalog
          racket -- "${src/generate-pkgs.rkt}" \
            -o "$out" \
            ${catalog}
        '';
      racket = pkgs.callPackage nix/racket.nix {};
    });

    devShells = perSystem ({
      pkgs,
      pkgs',
      ...
    }: {
      default = pkgs.mkShell {
        packages = [
          (pkgs'.racket.newLayer {
            withRacketPackages = ps: with ps; [graph-lib threading-lib];
          })
        ];
      };
    });

    formatter = perSystem ({pkgs, ...}: pkgs.alejandra);
  };
}
