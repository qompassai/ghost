# /qompassai/ghost/ghost/kresd.nix
# Qompass AI Ghost Kresd
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{ config, lib, ... }:
let cfg = config.ghost;
in
{
  config = lib.mkIf (cfg.enable && cfg.localDnsResolver) {
    services.kresd.enable = true;
  };
}
