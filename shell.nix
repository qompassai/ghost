# /qompassai/ghost/shell.nix
# Qompass AI Ghost Nix Shell
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
(import
  (
    let lock = builtins.fromJSON (builtins.readFile ./flake.lock); in
    fetchTarball {
      url = "https://github.com/edolstra/flake-compat/archive/${lock.nodes.flake-compat.locked.rev}.tar.gz";
      sha256 = lock.nodes.flake-compat.locked.narHash;
    }
  )
  { src = ./.; }
).shellNix
