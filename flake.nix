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
    packages = perSystem ({pkgs, ...}: rec {
      # TOOD: Very impure. Very bad.
      #       Should only be used for bootstrapping when a catalog isn't already present.
      #       No, actually it shouldn't even be used for that,
      #       but I don't have a better idea at the moment other than vendoring
      #       which I don't feel like doing.
      bootstrap = with pkgs; let
        racket-with-deps =
          runCommand "racket-nix-bootstrap" {
            buildInputs = [racket];
          } ''
            mkdir -p "$out/etc/racket"
            racket -- "${src/generate-config.rkt}" \
              --allow-user \
              --lookup-lib-env \
              "${racket}/etc/racket/config.rktd" \
              "$out" > "$out/etc/racket/config.rktd"
            racket -G "$out/etc/racket" -l- \
              raco setup \
              --trust-zos \
              --no-user \
              -j $NIX_BUILD_CORES
            "$out/bin/raco" pkg install \
              --installation \
              --copy \
              --batch \
              --no-cache \
              -j $NIX_BUILD_CORES \
              --deps search-auto \
              -D graph threading
          '';
        catalog = assert racket.version == "8.9";
          fetchurl {
            url = "https://pkgs.racket-lang.org/pkgs-all?version=${racket.version}";
            hash = "sha256-DGaVno9FaaLw26jSdLRYIKeTtRpMTjOC7hIn+qKG2RY=";
          };
      in
        runCommand "racket-pkgs" {
          nativeBuildInputs = [racket-with-deps];
        } ''
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
        packages = [pkgs.racket];
      };
    });

    formatter = perSystem ({pkgs, ...}: pkgs.alejandra);
  };
}
