# /qompassai/ghost/ghost/monit.nix
# Qompass AI Ghost Monitoring
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{ config, lib, ... }:
let
  cfg = config.ghost;
in
{
  config = lib.mkIf (cfg.enable && cfg.monitoring.enable) {
    services.monit = {
      enable = true;
      config = ''
        set alert ${cfg.monitoring.alertAddress}
        ${cfg.monitoring.config}
      '';
    };
  };
}
