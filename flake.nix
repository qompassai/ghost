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
    flake-utils.lib.eachDefaultSystem (system:
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
      testNames = [ "clamav" "external" "internal" "ldap" "multiple" ];
      genTest = testName: release:
        let
          pkgsR = release.pkgs;
          nixos-lib =
            import (release.nixpkgs + "/nixos/lib") { inherit (pkgsR) lib; };
        in
        {
          name = "${testName}-${
                builtins.replaceStrings [ "." ] [ "_" ] release.name
              }";
          value = nixos-lib.runTest {
            hostPkgs = pkgsR;
            imports = [ ./tests/${testName}.nix ];
            _module.args = { inherit blobs; };
            extraBaseModules.imports = [ ./default.nix ];
          };
        };
      allTests = lib.listToAttrs
        (lib.flatten (map (t: map (r: genTest t r) releases) testNames));
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
          optionsJson = builtins.toFile "options.json" (builtins.toJSON
            (lib.filter
              (opt: opt.visible && !opt.internal && lib.head opt.loc == "ghost")
              (lib.optionAttrSetToDocList eval.options)));
        in
        pkgs.runCommand "options.md"
          {
            nativeBuildInputs = [ pkgs.python3Minimal ];
          } ''
          echo "Generating options.md from ${optionsJson}"
          python ${./scripts/generate-options.py} ${optionsJson} > "$out"
        '';
      documentation = pkgs.stdenv.mkDerivation {
        name = "documentation";
        src = lib.sourceByRegex ./docs [
          "logo\\.png"
          "conf\\.py"
          "Makefile"
          ".*\\.rst"
        ];
        nativeBuildInputs = [
          (pkgs.python3.withPackages (p: [
            p.sphinx
            p.sphinx_rtd_theme
            p.myst-parser
            p.linkify-it-py
          ]))
          pkgs.makeWrapper
        ];
        buildPhase = ''
          cp ${optionsDoc} options.md
          unset SOURCE_DATE_EPOCH
          make html
        '';
        installPhase = ''
          cp -Tr _build/html "$out"
        '';
      };
      preCommit = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          markdownlint = {
            enable = true;
            settings.configuration = { MD013 = false; };
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
            args = [ "--extend-select" "I" ];
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
      mkApp = name: text:
        let drv = pkgs.writeShellScriptBin name text;
        in
        {
          type = "app";
          program = "${drv}/bin/${name}";
        };

    in
    {
      nixosModules = rec {
        ghost = ghostModule;
        default = ghost;
      };
      nixosModule = self.nixosModules.default;
      checks.${system} = allTests // { "pre-commit" = preCommit; };
      hydraJobs.${system} = allTests // {
        documentation = documentation;
        "pre-commit" = preCommit;
      };
      packages.${system} = {
        inherit optionsDoc documentation;
        default = optionsDoc;
      };
      defaultPackage.${system} = self.packages.${system}.default;
      devShells.${system}.default = pkgs.mkShellNoCC {
        inputsFrom = [ documentation ];
        packages = with pkgs; [ glab ] ++ preCommit.enabledPackages;
        shellHook = preCommit.shellHook;
      };
      devShell.${system} = self.devShells.${system}.default;
      apps.${system} = {
        default = mkApp "ghost-show-docs" ''
          echo "Documentation derivation is available; build with:"
          echo "  nix build .#documentation"
          echo
          echo "Options doc (options.md) is built by default:"
          echo "  nix build ."
        '';
        setup-secrets = mkApp "setup-secrets" ''
          set -euo pipefail
          CFG="$XDG_CONFIG_HOME"
          if [ -z "$CFG" ]; then CFG="$HOME/.config"; fi
          mkdir -p "$CFG/ghost/ssl"
          export SOPS_AGE_KEY_FILE="$CFG/ghost/age.key"
          export SOPS_GPG_KEY=""
          ${pkgs.sops}/bin/sops -d --extract '["ghost"]["ssl"]["fullchain.pem"]' ./secrets.yaml > "$CFG/ghost/ssl/fullchain.pem"
          ${pkgs.sops}/bin/sops -d --extract '["ghost"]["ssl"]["privkey.pem"]'   ./secrets.yaml > "$CFG/ghost/ssl/privkey.pem"
          ${pkgs.sops}/bin/sops -d --extract '["ghost"]["ssl"]["dkim.key"]'      ./secrets.yaml > "$CFG/ghost/ssl/dkim.key"
          echo "Secrets written under $CFG/ghost/ssl"
        '';
        mk-symlinks = mkApp "mk-symlinks" ''
          set -euo pipefail
          CFG="$XDG_CONFIG_HOME"
          if [ -z "$CFG" ]; then CFG="$HOME/.config"; fi
          mkdir -p "$CFG/dovecot/ssl"
          ln -sf "$CFG/ghost/ssl/fullchain.pem" "$CFG/dovecot/ssl/fullchain.pem"
          ln -sf "$CFG/ghost/ssl/privkey.pem"   "$CFG/dovecot/ssl/privkey.pem"
          echo "Symlinks created under $CFG/dovecot/ssl"
        '';
        print-units = mkApp "print-units" ''
          cat ${./systemd-user/dovecot.service}
          cat ${./systemd-user/nginx.service}
          cat ${./systemd-user/rspamd.service}
        '';
        mail-init = mkApp "mail-init" ''
          set -euo pipefail
          DATA="$XDG_DATA_HOME"
          if [ -z "$DATA" ]; then DATA="$HOME/.local/share"; fi
          RUN="$XDG_RUNTIME_DIR"
          if [ -z "$RUN" ]; then RUN="/run/user/$(id -u)"; fi
          mkdir -p "$DATA/mail/testuser"
          : > "$RUN/mail-test.sock"
          echo "Mail and runtime socket set up:"
          echo "  $DATA/mail/testuser"
          echo "  $RUN/mail-test.sock"
        '';
        setup = mkApp "setup" ''
          set -euo pipefail
          nix run .#setup-secrets
          nix run .#mk-symlinks
          echo
          echo "Copy systemd units to \$XDG_CONFIG_HOME/systemd/user/ and enable/start:"
          echo "  systemctl --user daemon-reload"
          echo "  systemctl --user enable dovecot && systemctl --user start dovecot"
          echo "  systemctl --user enable nginx   && systemctl --user start nginx"
          echo "  systemctl --user enable rspamd  && systemctl --user start rspamd"
        '';
        start-all = mkApp "start-all" ''
          set -euo pipefail
          systemctl --user daemon-reload
          systemctl --user start dovecot
          systemctl --user start nginx
          systemctl --user start rspamd
        '';
        stop-all = mkApp "stop-all" ''
          set -euo pipefail
          systemctl --user stop dovecot || true
          systemctl --user stop nginx  || true
          systemctl --user stop rspamd || true
        '';
      };
    });
}




