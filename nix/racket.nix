{
  # TODO: Eventually bootstrap and build racket ourselves
  racket-minimal,
  callPackage,
  stdenvNoCC,
  symlinkJoin,
  fetchzip,
  lib,
}: let
  collectDeps = deps: let
    depsDeps = lib.foldl (acc: curr: acc ++ curr.racketDeps) [] deps;
    depsDeps' = lib.unique depsDeps;
    depsRecur =
      if depsDeps' == []
      then []
      else collectDeps depsDeps';
    depsRecur' = lib.unique depsRecur;
  in
    lib.unique (deps ++ depsDeps' ++ depsRecur');
  fetchzip' = args:
    fetchzip
    (args
      // {
        stripRoot = false;
        # At unpack time decide whether to stripRoot or not
        postFetch = ''
          shopt -s nullglob
          ALL_FILES=( "$out"/* )
          if [[ "''${#ALL_FILES[@]}" == 1 ]]; then
            mv "$out" "$unpackDir"
            MAIN_PATH=$(basename "''${ALL_FILES[0]}")
            mv "$unpackDir/$MAIN_PATH" "$out"
            rm -rf "$unpackDir"
          fi
        '';
      });
  pkgs = callPackage ../racket-pkgs.nix {
    fetchzip = fetchzip';
    mkRacketPackage = callPackage ./mk-racket-package.nix {};
  };
  createCatalog = paths:
    symlinkJoin {
      name = "racket-catalog";
      inherit paths;
    };
  newLayer = prevLayer: defaultLookupLib: {
    allowUser ? null,
    lookupLibEnv ? defaultLookupLib,
    buildInputs ? [],
    withRacketPackages ? (_: []),
    racketInputs ? [],
  }:
    stdenvNoCC.mkDerivation (final: let
      prevDeps = prevLayer.racketInputs or [];
      deps = (withRacketPackages pkgs) ++ racketInputs;
      allDeps = collectDeps deps;
      installDeps = lib.optionalString (deps != []) ''
        "$out/bin/raco" pkg install \
          --installation \
          --copy \
          --batch \
          --no-cache \
          -j $NIX_BUILD_CORES \
          --deps search-auto \
          --catalog "file://$racketCatalog" \
          --skip-installed \
          -D \
          ${lib.escapeShellArgs (map (dep: dep.name) deps)}
      '';
    in {
      name = "${prevLayer.name or prevLayer.pname}-layered";
      buildInputs = [prevLayer] ++ buildInputs;

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;

      userLayer =
        if allowUser == true
        then "--allow-user"
        else if allowUser == false
        then "--deny-user"
        else null;
      lookupLib =
        if lookupLibEnv == true
        then "--lookup-lib-env"
        else if lookupLibEnv == false
        then "--no-lookup-lib-env"
        else null;
      extraLibs = lib.makeLibraryPath buildInputs;
      racketCatalog = createCatalog allDeps;

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/etc/racket"

        "${prevLayer}/bin/racket" -- ${../src/generate-config.rkt} \
          ''${userLayer:+"$userLayer"} \
          ''${lookupLib:+"$lookupLib"} \
          --extra-lib-paths "$extraLibs" \
          --catalog-path "file://$racketCatalog" \
          "${prevLayer}/etc/racket/config.rktd" \
          "$out" > "$out/etc/racket/config.rktd"
        "${prevLayer}/bin/racket" -G "$out/etc/racket" -l- \
          raco setup \
            --trust-zos \
            --no-user \
            -j $NIX_BUILD_CORES
        ${installDeps}

        runHook postInstall
      '';

      passthru = {
        # All packages avaliable in this layer
        racketInputs = deps ++ prevDeps;
        newLayer = newLayer final.finalPackage null;
        inherit pkgs;
      };
    });
in
  racket-minimal.overrideAttrs (final: prev: {
    passthru =
      (prev.passthru or {})
      // {
        newLayer = newLayer final.finalPackage true;
        inherit pkgs;
      };
  })
