#!/usr/bin/env bash

if [[ -f racket-pkgs.nix ]]; then
  echo DO NOT BOOTSTRAP IF racket-pkgs.nix IS ALREADY PRESENT >&2
  echo IT\'S IMPURE AND SHOULD BE AVOIDED WHENEVER IT CAN BE  >&2
  exit 1
fi

RACKET_PKGS=$(nix build --no-link --print-out-paths .#bootstrap)
cp "$RACKET_PKGS" ./racket-pkgs.nix
