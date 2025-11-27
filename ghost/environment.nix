# /qompassai/ghost/ghost/environment.nix
# Qompass AI Ghost Environment
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{ config, pkgs, lib, ... }:
let cfg = config.ghost;
in
{
  config = with cfg;
    lib.mkIf enable {
      environment.systemPackages = with pkgs;
        [ dovecot openssh postfix rspamd ]
        ++ (if certificateScheme == "selfsigned" then [ openssl ] else [ ]);
    };
}
