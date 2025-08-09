# /qompassai/ghost/flake.nix
# Qompass AI Ghost Flake
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{
  description = "Qompass AI Ghost Protocol";
  inputs = {
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-25_05.url = "github:NixOS/nixpkgs/nixos-25.05";
    blobs = {
      url = "github:qompassai/blobs";
      flake = false;
    };
    sops-nix.url = "github:Mic92/sops-nix";
    flake-utils.url = "github:numtide/flake-utils";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.flake-compat.follows = "flake-compat";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    { self
    , blobs
    , git-hooks
    , nixpkgs
    , nixpkgs-25_05
    , sops-nix
    , flake-utils
    , ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        lib = nixpkgs.lib;
        pkgs = nixpkgs.legacyPackages.${system};
        releases = [
          {
            name = "unstable";
            nixpkgs = nixpkgs;
            pkgs = nixpkgs.legacyPackages.${system};
          }
          {
            name = "25.05";
            nixpkgs = nixpkgs-25_05;
            pkgs = nixpkgs-25_05.legacyPackages.${system};
          }
        ];
        testNames = [
          "clamav"
          "external"
          "internal"
          "ldap"
          "multiple"
        ];
        genTest =
          testName: release:
          let
            pkgs = release.pkgs;
            nixos-lib = import (release.nixpkgs + "/nixos/lib") { inherit (pkgs) lib; };
          in
          {
            name = "${testName}-${builtins.replaceStrings [ "." ] [ "_" ] release.name}";
            value = nixos-lib.runTest {
              hostPkgs = pkgs;
              imports = [ ./tests/${testName}.nix ];
              _module.args = { inherit blobs; };
              extraBaseModules.imports = [ ./default.nix ];
            };
          };
        allTests = lib.listToAttrs (lib.flatten (map (t: map (r: genTest t r) releases) testNames));
        ghostModule = import ./.;
        optionsDoc =
          let
            eval = lib.evalModules {
              modules = [
                ghostModule
                {
                  _module.check = false;
                  ghost = {
                    fqdn = "mx.example.com";
                    domains = [ "example.com" ];
                    dmarcReporting = {
                      organizationName = "Example Corp";
                      domain = "example.com";
                    };
                  };
                }
              ];
            };
            options = builtins.toFile "options.json" (
              builtins.toJSON (
                lib.filter (opt: opt.visible && !opt.internal && lib.head opt.loc == "ghost") (
                  lib.optionAttrSetToDocList eval.options
                )
              )
            );
          in
          pkgs.runCommand "options.md"
            {
              buildInputs = [ pkgs.python3Minimal ];
            }
            ''
              echo "Generating options.md from ${options}"
              python ${./scripts/generate-options.py} ${options} > $out
              echo $out
            '';
        documentation = pkgs.stdenv.mkDerivation {
          name = "documentation";
          src = lib.sourceByRegex ./docs [
            "logo\\.png"
            "conf\\.py"
            "Makefile"
            ".*\\.rst"
          ];
          buildInputs = [
            (pkgs.python3.withPackages (p: [
              p.sphinx
              p.sphinx_rtd_theme
              p.myst-parser
              p.linkify-it-py
            ]))
          ];
          buildPhase = ''
              cp ${optionsDoc} options.md
            unset SOURCE_DATE_EPOCH
            make html
          '';
          installPhase = ''
            cp -Tr _build/html $out
          '';
        };
        pre-commit = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            markdownlint = {
              enable = true;
              settings.configuration = {
                MD013 = false;
              };
            };
            rstcheck = {
              enable = true;
              package = pkgs.rstcheckWithSphinx;
              entry = lib.getExe pkgs.rstcheckWithSphinx;
              files = "\\.rst$";
            };
            deadnix.enable = true;
            pyright.enable = true;
            ruff = {
              enable = true;
              args = [
                "--extend-select"
                "I"
              ];
            };
            ruff-format.enable = true;
            shellcheck.enable = true;
            check-sieve = {
              enable = true;
              package = pkgs.check-sieve;
              entry = lib.getExe pkgs.check-sieve;
              files = "\\.sieve$";
            };
          };
        };
      in
      {
        nixosModules = rec {
          ghost = ghostModule;
          default = ghost;
        };
        nixosModule = self.nixosModules.default;
        hydraJobs.${system} = allTests // {
          inherit documentation;
          inherit (self.checks.${system}) pre-commit;
        };
        checks.${system} = allTests // {
          pre-commit = pre-commit;
        };
        packages.${system} = {
          inherit optionsDoc documentation;
          default = optionsDoc;
        };
        devShells.${system}.default = pkgs.mkShellNoCC {
          inputsFrom = [ documentation ];
          packages = with pkgs; [ glab ] ++ self.checks.${system}.pre-commit.enabledPackages;
          shellHook = self.checks.${system}.pre-commit.shellHook;
        };
        devShell.${system} = self.devShells.${system}.default;
        apps.${system} = {
          setup-secrets = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "setup-secrets" ''
                set -e
                export SOPS_AGE_KEY_FILE="$XDG_CONFIG_HOME/ghost/age.key"
                export SOPS_GPG_KEY=""
                ${pkgs.sops}/bin/sops -d --extract '["ghost"]["ssl"]["fullchain.pem"]' ./secrets.yaml > $XDG_CONFIG_HOME/ghost/ssl/fullchain.pem
                ${pkgs.sops}/bin/sops -d --extract '["ghost"]["ssl"]["privkey.pem"]' ./secrets.yaml > $XDG_CONFIG_HOME/ghost/ssl/privkey.pem
                ${pkgs.sops}/bin/sops -d --extract '["ghost"]["ssl"]["dkim.key"]' ./secrets.yaml > $XDG_CONFIG_HOME/ghost/ssl/dkim.key
              ''
            );
          };
          mk-symlinks = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "mk-symlinks" ''
                set -e
                mkdir -p $XDG_CONFIG_HOME/dovecot/ssl
                ln -sf $XDG_CONFIG_HOME/ghost/ssl/fullchain.pem $XDG_CONFIG_HOME/dovecot/ssl/fullchain.pem
                ln -sf $XDG_CONFIG_HOME/ghost/ssl/privkey.pem $XDG_CONFIG_HOME/dovecot/ssl/privkey.pem
              ''
            );
          };
          print-units = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "print-units" ''
                cat ${./systemd-user/dovecot.service}
                cat ${./systemd-user/nginx.service}
                cat ${./systemd-user/rspamd.service}
              ''
            );
          };
          mail-init = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "mail-init" ''
                mkdir -p $XDG_DATA_HOME/mail/testuser
                touch $XDG_RUNTIME_DIR/mail-test.sock
                echo "Mail and runtime socket set up in data/runtime dirs per XDG conventions"
              ''
            );
          };
          setup = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "setup" ''
                nix run .#setup-secrets
                nix run .#mk-symlinks
                echo "Copy systemd units to \$XDG_CONFIG_HOME/systemd/user/ and enable/start each:"
                echo "  systemctl --user daemon-reload"
                echo "  systemctl --user enable dovecot"
                echo "  systemctl --user start dovecot"
              ''
            );
          };
          start-all = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "start-all" ''
                systemctl --user daemon-reload
                systemctl --user start dovecot
                systemctl --user start nginx
                systemctl --user start rspamd
              ''
            );
          };
          stop-all = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "stop-all" ''
                systemctl --user stop dovecot || true
                systemctl --user stop nginx || true
                systemctl --user stop rspamd || true
              ''
            );
          };
        };
      }
    );
}
