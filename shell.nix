# /qompassai/ghost/shell.nix
# Qompass AI Ghost Nix Shell
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  flake-compat = import (fetchTarball {
    url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev}.tar.gz";
    sha256 = lock.nodes.flake-compat.locked.narHash;
  });
  fc = flake-compat { src = ./.; };
  system = builtins.currentSystem;
in
if builtins.hasAttr "devShells" fc.outPath // {}
then (import ./.).devShells.${system}.default
else fc.shellNix
