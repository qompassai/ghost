# /qompassai/ghost/flake.nix
# ---------------------
# Copyright (C) 2025 Qompass AI, All rights reserved

{
  description = "Qompass AI Gateway Hosting Onion Secure Transport ("Ghost") Protocol Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, mailserver }: 
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ mailserver.overlay ];
        };
      in {
        nixosModules.ghost = { config, ... }: {
          imports = [ mailserver.nixosModule ];

          options.ghost = {
            enable = pkgs.lib.mkEnableOption "Qompass Ghost mail server";
            domain = pkgs.lib.mkOption {
              type = pkgs.lib.types.str;
              default = "qompass.ai";
            };
          };

          config = pkgs.lib.mkIf config.ghost.enable {
            mailserver = {
              enable = true;
              fqdn = "mail.${config.ghost.domain}";
              domains = [ config.ghost.domain ];

              certificateScheme = "selfsigned";
              certificateFile = "/etc/postfix/qompassai-mail.chain";
              keyFile = "/etc/postfix/qompassai-mail.key";

              vmailUserName = "vmail";
              vmailGroupName = "vmail";
              vmailUID = 5000;
              vmailGID = 5000;

              enableImap = true;
              enablePop3 = true;
              enableManageSieve = true;
              enableClamAV = true;
              enableSpamAssassin = true;
              enableRspamd = true;
              enableUnbound = true;
            };

            security = {
              dhparams.enable = true;
              dhparams.params = {
                nginx = 4096;
                dovecot = 4096;
                prosody = 4096;
              };
            };

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

              nginx = {
                enable = true;
                recommendedTlsSettings = true;
                recommendedOptimisation = true;
                virtualHosts."mail.${config.ghost.domain}" = {
                  root = "/var/www/html";
                  locations."/".extraConfig = ''
                    index index.php;
                  '';
                };
              };
            };

            systemd = {
              tmpfiles.rules = [
                "d /var/mail/vmail 0755 vmail vmail"
                "d /var/www/mail 0755 www-data www-data"
                "d /var/lib/rspamd/dkim 0755 _rspamd _rspamd"
              ];

              services.ghost-init = {
                description = "Qompass Ghost initialization";
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = pkgs.writeScript "ghost-init" ''
                    #!/bin/sh
                    ${pkgs.openssl}/bin/openssl ecparam -name secp521r1 -genkey | \
                      ${pkgs.openssl}/bin/openssl pkey -out /etc/dovecot/ecprivkey.pem
                    ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 3650 \
                      -newkey ed448 -subj "/CN=mail.${config.ghost.domain}" \
                      -keyout /etc/postfix/qompassai-mail.key \
                      -out /etc/postfix/qompassai-mail.crt
                  '';
                };
              };
            };
          };
        };

        packages.default = pkgs.callPackage ({ stdenv }: 
          stdenv.mkDerivation {
            name = "ghost-mailserver";
            src = self;
            installPhase = "mkdir -p $out";
          }) {};
      }
    );
}
