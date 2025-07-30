# /qompassai/ghost/ghost/clamav.nix
# Qompass AI Ghost Clamav
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################

{ config, lib, ... }:

let
  cfg = config.ghost;
in
{
  config = lib.mkIf (cfg.enable && cfg.virusScanning) {
    services.clamav.daemon = {
      enable = true;
      settings.PhishingScanURLs = "no";
    };
    services.clamav.updater.enable = true;
  };
}
