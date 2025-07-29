# /qompassai/ghost/flake.nix
# Qompass AI Ghost Flake
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{
  description = "Qompass AI Ghost Protocol ";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, sops-nix, flake-utils, mailserver }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        xdg_config = "$XDG_CONFIG_HOME";
        xdg_data = "$XDG_DATA_HOME";
        xdg_runtime = "$XDG_RUNTIME_DIR";
      in
      {
        packages.default = pkgs.buildEnv {
          name = "ghost";
          paths = with pkgs; [
            bash-completion
            bind
            clamav
            curl
            dovecot
            git
            gnupg
            haveged
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
            sops
            age
          ];
        };
        apps."${system}".setup-secrets = {
          type = "app";
          program = toString (pkgs.writeShellScript "setup-secrets" ''
            set -e
            export SOPS_AGE_KEY_FILE="$XDG_CONFIG_HOME/ghost/age.key"
            export SOPS_GPG_KEY=""
            ${pkgs.sops}/bin/sops -d --extract '["ghost"]["ssl"]["fullchain.pem"]' ./secrets.yaml > $XDG_CONFIG_HOME/ghost/ssl/fullchain.pem
            ${pkgs.sops}/bin/sops -d --extract '["ghost"]["ssl"]["privkey.pem"]' ./secrets.yaml > $XDG_CONFIG_HOME/ghost/ssl/privkey.pem
            ${pkgs.sops}/bin/sops -d --extract '["ghost"]["ssl"]["dkim.key"]' ./secrets.yaml > $XDG_CONFIG_HOME/ghost/ssl/dkim.key
            # Add more secrets as needed
          '');
        };
        apps."${system}".mk-symlinks = {
          type = "app";
          program = toString (pkgs.writeShellScript "mk-symlinks" ''
            set -e
            mkdir -p ${xdg_config}/dovecot/ssl
            ln -sf ${xdg_config}/ghost/ssl/fullchain.pem ${xdg_config}/dovecot/ssl/fullchain.pem
            ln -sf ${xdg_config}/ghost/ssl/privkey.pem ${xdg_config}/dovecot/ssl/privkey.pem
          '');
        };
        apps."${system}".print-units = {
          type = "app";
          program = toString (pkgs.writeShellScript "print-units" ''
            cat ${./systemd-user/dovecot.service}
            cat ${./systemd-user/nginx.service}
            cat ${./systemd-user/rspamd.service}
          '');
        };
        apps."${system}".mail-init = {
          type = "app";
          program = toString (pkgs.writeShellScript "mail-init" ''
            mkdir -p ${xdg_data}/mail/testuser
            touch ${xdg_runtime}/mail-test.sock
            echo "Mail and runtime socket set up in data/runtime dirs per XDG conventions"
          '');
        };
        apps."${system}".setup = {
          type = "app";
          program = toString (pkgs.writeShellScript "setup" ''
            nix run .#setup-secrets
            nix run .#mk-symlinks
            echo "Copy systemd units to \$XDG_CONFIG_HOME/systemd/user/ and enable/start each:"
            echo "  systemctl --user daemon-reload"
            echo "  systemctl --user enable dovecot"
            echo "  systemctl --user start dovecot"
            # ...repeat as needed for other services
          '');
        };
        apps."${system}".start-all = {
          type = "app";
          program = toString (pkgs.writeShellScript "start-all" ''
            systemctl --user daemon-reload
            systemctl --user start dovecot
            systemctl --user start nginx
            systemctl --user start rspamd
            # etc.
          '');
        };
        apps."${system}".stop-all = {
          type = "app";
          program = toString (pkgs.writeShellScript "stop-all" ''
            systemctl --user stop dovecot || true
            systemctl --user stop nginx || true
            systemctl --user stop rspamd || true
            # etc.
          '');
        };
        nixosModules.ghost = { config, ... }: {
        imports = [ mailserver.nixosModule ];
        options.ghost = {
          enable = pkgs.lib.mkEnableOption "Qompass AI Ghost mail server";
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
        };
      };
      });
}
