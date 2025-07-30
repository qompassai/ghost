# /qompassai/ghost/ghost/systemd.nix
# Qompass AI Ghost Systemd
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{ config, pkgs, lib, ... }:
let
  cfg = config.ghost;
  certificatesDeps =
    if cfg.certificateScheme == "manual" then
      []
    else if cfg.certificateScheme == "selfsigned" then
      [ "ghost-selfsigned-certificate.service" ]
    else
      [ "acme-finished-${cfg.fqdn}.target" ];
in
{
  config = with cfg; lib.mkIf enable {
    systemd.services.ghost-selfsigned-certificate = lib.mkIf (cfg.certificateScheme == "selfsigned") {
      after = [ "local-fs.target" ];
      script = ''
        # Create certificates if they do not exist yet
        dir="${cfg.certificateDirectory}"
        fqdn="${cfg.fqdn}"
        [[ $fqdn == /* ]] && fqdn=$(< "$fqdn")
        key="$dir/key-${cfg.fqdn}.pem";
        cert="$dir/cert-${cfg.fqdn}.pem";

        if [[ ! -f $key || ! -f $cert ]]; then
            mkdir -p "${cfg.certificateDirectory}"
            (umask 077; "${pkgs.openssl}/bin/openssl" genrsa -out "$key" 2048) &&
                "${pkgs.openssl}/bin/openssl" req -new -key "$key" -x509 -subj "/CN=$fqdn" \
                        -days 3650 -out "$cert"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        PrivateTmp = true;
      };
    };
    systemd.services.dovecot2 = {
      wants = certificatesDeps;
      after = certificatesDeps;
      preStart = let
        directories = lib.strings.escapeShellArgs (
          [ mailDirectory ]
          ++ lib.optional (cfg.indexDir != null) cfg.indexDir
        );
      in ''
        # Create mail directory and set permissions. See
        # <https://doc.dovecot.org/main/core/config/shared_mailboxes.html#filesystem-permissions-1>.
        # Prevent world-readable paths, even temporarily.
        umask 007
        mkdir -p ${directories}
        chgrp "${vmailGroupName}" ${directories}
        chmod 02770 ${directories}
      '';
    };

    systemd.services.postfix = {
      wants = certificatesDeps;
      after = [ "dovecot2.service" ]
        ++ lib.optional cfg.dkimSigning "rspamd.service"
        ++ certificatesDeps;
      requires = [ "dovecot2.service" ]
        ++ lib.optional cfg.dkimSigning "rspamd.service";
    };
  };
}
