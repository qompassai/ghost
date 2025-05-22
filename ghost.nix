# /qompassai/ghost/flake.nix
# ---------------------
# Copyright (C) 2025 Qompass AI, All rights reserved

{ config, pkgs, lib, ... }:

let
  workingDir = "/var/lib/qompass-mailsetup";
in {
  imports = [
    ./hardware-configuration.nix
  ];

  system.stateVersion = "25.05";

  environment.systemPackages = with pkgs; [
    bash-completion
    bind
    clamav
    curl
    dovecot
    git
    gnupg
    haveged
    iptables
    lua
    mariadb
    mercurial
    nano
    nginx
    openssl
    patch
    php82
    postfix
    prosody
    redis
    rspamd
    tor
    vim
    wget
    unzip
    wireguard-tools
  ];

  services = {
    mysql = {
      enable = true;
      package = pkgs.mariadb;
      initialScript = pkgs.writeText "mysql-init" ''
        CREATE DATABASE IF NOT EXISTS mail;
        USE mail;
        /* Add your SQL schema here */
      '';
    };

    dovecot = {
      enable = true;
      extraConfig = ''
        ssl_cert = </etc/postfix/qompassai-mail.chain
        ssl_key = </etc/postfix/qompassai-mail.key
      '';
    };

    nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      virtualHosts."mail.qompass.ai" = {
        root = "/var/www/html";
        locations."/".extraConfig = ''
          index index.php;
        '';
      };
    };

    postfix = {
      enable = true;
      sslCert = "/etc/postfix/qompassai-mail.chain";
      sslKey = "/etc/postfix/qompassai-mail.key";
    };

    rspamd.enable = true;
    clamav.daemon.enable = true;
    redis.enable = true;
  };

  security = {
    dhparams = {
      enable = true;
      params.nginx = 4096;
      params.dovecot = 4096;
      params.prosody = 4096;
    };
  };

  users = {
    users = {
      vmail = {
        isSystemUser = true;
        group = "vmail";
        uid = 5000;
        home = "/var/mail/vmail";
      };
      www-data.extraGroups = [ "vmail" ];
    };
    groups.vmail.gid = 5000;
  };

  systemd = {
    tmpfiles.rules = [
      "d /var/mail/vmail 0755 vmail vmail"
      "d /var/www/mail 0755 www-data www-data"
      "d /var/lib/rspamd/dkim 0755 _rspamd _rspamd"
    ];

    services = {
      mailsetup = {
        description = "Qompass AI Mail Server Setup";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = workingDir;
        };
        script = ''
          # Generate encryption keys
          ${pkgs.openssl}/bin/openssl rand -hex 128 > /etc/mysql/encryption/keyfile.key
          echo "1;"$(${pkgs.openssl}/bin/openssl rand -hex 32) | \
            ${pkgs.openssl}/bin/openssl enc -aes-256-cbc -md sha1 -pass file:/etc/mysql/encryption/keyfile.key \
            -out /etc/mysql/encryption/keyfile.enc

          # Generate EC keys
          ${pkgs.openssl}/bin/openssl ecparam -name secp521r1 -genkey | \
            ${pkgs.openssl}/bin/openssl pkey -out /etc/dovecot/ecprivkey.pem
          ${pkgs.openssl}/bin/openssl pkey -in /etc/dovecot/ecprivkey.pem -pubout \
            -out /etc/dovecot/ecpubkey.pem

          # Generate certificate chain
          ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 3650 -newkey ed448 \
            -subj "/" -keyout /etc/postfix/qompassai-mail.key \
            -out /etc/postfix/qompassai-mail.crt
          cat /etc/postfix/qompassai-mail.key >> /etc/postfix/qompassai-mail.chain
          cat /etc/postfix/qompassai-mail.crt >> /etc/postfix/qompassai-mail.chain
        '';
      };

      squirrelmail = {
        description = "SquirrelMail Setup";
        wantedBy = [ "multi-user.target" ];
        after = [ "nginx.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = "${workingDir}/squirrelmail";
        };
        script = ''
          ${pkgs.git}/bin/git clone https://github.com/RealityRipple/squirrelmail .
          mkdir -p /var/local/squirrelmail/{data,attach}
          chown www-data:www-data -R /var/local/squirrelmail
          cp ${./squirrelmail_config.php} config/config.php
        '';
      };
    };
  };

  environment.etc = {
    "rspamd/dkim.conf".text = ''
      path = "/var/lib/rspamd/dkim";
    '';
  };
}

