# /qompassai/ghost/tests/lib/config.nix
# Qompass AI Ghost Test Lib Config
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{
  lib,
  ...
}:
{
  mailserver.stateVersion = 999;
  virtualisation.cores = lib.mkDefault 2;
  services.rspamd.locals."options.inc".text = ''
    dns {
       nameservers = ["127.0.0.1", "::1"];
      # nameservers = ["127.0.0.1", "::1", "127.0.0.1:9053", "[::1]:9053"];
      timeout = 0.0s;
      retransmits = 0;
    }
  '';
}
