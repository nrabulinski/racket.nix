{
  runCommand,
  racket-minimal,
  lib,
}: {
  name,
  src,
  checksum,
  racketDeps ? [],
  cyclicDeps ? [],
} @ pkg: let
  allPkgs = [pkg] ++ cyclicDeps;
  makePkg = {
    name,
    src,
    checksum,
    ...
  }: ''
    racket -- ${../src/create-pkg.rkt} \
      --checksum ${lib.escapeShellArg checksum} \
      ${lib.escapeShellArg src} \
      > "$out/pkg/"${lib.escapeShellArg name}
  '';
  pkgCommands = lib.concatMapStringsSep "\n" makePkg allPkgs;
in
  runCommand name {
    nativeBuildInputs = [racket-minimal];
    passthru = {inherit racketDeps;};
  } ''
    mkdir -p "$out/pkg"
    ${pkgCommands}
  ''
