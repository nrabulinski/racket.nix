# racket.nix

Making Racket usable within the Nix ecosystem.

Currently it's very impure and very unstable.
The plan is to not change the `newLayer` API much, but there's also no commitment at this point.

Dependency resolution doesn't fully work yet so if you get an error about a package not being available,
just add it to the list of packages. (For now, obviously)

## Example usage
```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    racket = {
      url = "github:nrabulinski/racket.nix";
      inputs.nixpkgs.follows = "nixpkgs";  
    };
  };

  outputs = { nixpkgs, racket, ... }: let
    forAllSystems = nixpkgs.lib.genAttrs [
      "aarch64-linux"
      "aarch64-darwin"
      "x86_64-linux"
      "x86_64-darwin"
    ];
  in {
    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      racket' = racket.packages.${system}.racket;
      racket-with-libs = racket'.newLayer {
        # Racket package dependencies
        withRacketPackages = ps: with ps; [ graph threading ];
        # Native dependencies
        buildInputs = with pkgs; [ openssl ];
      };
    in {
      default = pkgs.mkShell {
        packages = [ racket-with-libs ];
      };
    });
  };
}
```

## Acknowledgements
@LiberalArtist and their [https://gitlab.com/philip1/guix-racket-experiment](guix-racket-experiment) project
who has been a huge inspiration and who's approach I've basically copied verbatim.