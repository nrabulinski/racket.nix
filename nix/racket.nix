{
  # TODO: Eventually bootstrap and build racket ourselves
  racket-minimal,
  callPackage,
  stdenvNoCC,
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
    lib.unique ((map (dep: dep.name) (deps ++ depsDeps')) ++ depsRecur');
  pkgs = callPackage ../racket-pkgs.nix {};
  newLayer = prevLayer: defaultLookupLib: {
    allowUser ? null,
    lookupLibEnv ? defaultLookupLib,
    buildInputs ? [],
    withRacketPackages ? (_: []),
    racketInputs ? [],
  }:
    stdenvNoCC.mkDerivation (final: let
      prevDeps = prevLayer.racketInputs or [];
      deps = racketInputs ++ (withRacketPackages pkgs);
      filteredDeps = lib.filter (dep: ! lib.elem dep prevDeps) deps;
      allDeps = collectDeps filteredDeps;
      installDeps = lib.optionalString (allDeps != []) ''
        "$out/bin/raco" pkg install \
          --installation \
          --copy \
          --batch \
          --no-cache \
          -j $NIX_BUILD_CORES \
          --deps search-auto \
          -D \
          ${lib.escapeShellArgs allDeps}
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

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/etc/racket"

        "${prevLayer}/bin/racket" -- ${../src/generate-config.rkt} \
          ''${userLayer:+"$userLayer"} \
          ''${lookupLib:+"$lookupLib"} \
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
