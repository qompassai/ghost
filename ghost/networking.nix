# /qompassai/ghost/ghost/networking.nix
# Qompass AI Ghost Networking
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{ config, lib, ... }:

let cfg = config.ghost;
in
{
  config = with cfg;
    lib.mkIf (enable && openFirewall) {
      networking.firewall = {
        allowedTCPPorts = [ 2525 ] ++ lib.optional enableSubmission 1587
          ++ lib.optional enableSubmissionSsl 1465 ++ lib.optional enableImap 1143
          ++ lib.optional enableImapSsl 1993 ++ lib.optional enablePop3 1110
          ++ lib.optional enablePop3Ssl 1995
          ++ lib.optional enableManageSieve 5190
          ++ lib.optional (certificateScheme == "acme-nginx") 8080;
      };
    };
}
