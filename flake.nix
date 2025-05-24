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

            security.dhparams = {
            enable = true;
            nginx.bitSize = 4096;
            dovecot2.bitSize = 4096;
            prosody.bitSize = 4096;
            };

            services = {
              mysql = {
                enable = true;
                package = pkgs.mariadb;
                initialScript = pkgs.writeText "mysql-init" ''
                CREATE DATABASE IF NOT EXISTS mail;
                USE mail;
                CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                email VARCHAR(255) NOT NULL,
                password_hash VARCHAR(255) NOT NULL
                );
                '';
              };

              nginx = {
                enable = true;
                recommendedTlsSettings = true;
                recommendedOptimisation = true;
               services.nginx.virtualHosts."mail.${config.ghost.domain}" = {
               root = "/var/www/html";
               locations."/".extraConfig = ''
               index index.php;
               '';
               locations."~ \.php$".extraConfig = ''
               fastcgi_pass unix:${config.services.phpfpm.pools."www".socket};
               include ${pkgs.nginx}/conf/fastcgi_params;
               '';
               };
               services.phpfpm.pools."www" = {
               user = "www-data";
               group = "www-data";
               settings = {
               "listen.owner" = "www-data";
               "listen.group" = "www-data";
               };
               };

             environment.systemPackages = with pkgs; [
             bash-completion
             bind
             curl
             git
             gnupg
             nano
             vim
             wget
             unzip
             clamav
             dovecot
             openssl
             postfix
             rspamd
             wireguard-tools
             
             (php.buildEnv {
             extensions = { enabled, all }: enabled ++ (with all; [
             gd gmp imap intl mbstring mysql pspell tidy uuid xml zip
             ]);
             })

    squirrelmail = pkgs.fetchFromGitHub {
    owner = "RealityRipple";
    repo = "squirrelmail";
    rev = "master";
    sha256 = "0nac19qgplhm08ggp5a2hxbph4vfi2dd24prn38s0yhmvayg1igp";
    };
    
    snappymail = pkgs.fetchFromGitHub {
    owner = "the-djmaze";
    repo = "snappymail";
    rev = "v2.29.0";
    sha256 = "1wdvs43zs9p0gw2kmkmfwmvxczs6f409rx26f3pc16rff8381smz";
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
    erviceConfig = {
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
