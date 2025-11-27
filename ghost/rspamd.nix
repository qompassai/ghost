# /qompassai/ghost/ghost/rspamd.nix
# Qompass AI Ghost RSpamd
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{ config, pkgs, lib, ... }:
let
  xdgRuntime = ["$XDG_RUNTIME_DIR"];
  cfg = config.ghost;
  postfixCfg = config.services.postfix;
  rspamdCfg = config.services.rspamd;
  rspamdSocket = "rspamd.service";
  rspamdUser = config.services.rspamd.user;
  rspamdGroup = config.services.rspamd.group;
  createDkimKeypair = domain:
    let
      privateKey = "${cfg.dkimKeyDirectory}/${domain}.${cfg.dkimSelector}.key";
      publicKey = "${cfg.dkimKeyDirectory}/${domain}.${cfg.dkimSelector}.txt";
    in
    pkgs.writeShellScript "dkim-keygen-${domain}" ''
      if [ ! -f "${privateKey}" ]
      then
        ${lib.getExe' pkgs.rspamd "rspamadm"} dkim_keygen \
          --domain "${domain}" \
          --selector "${cfg.dkimSelector}" \
          --type "${cfg.dkimKeyType}" \
          --bits ${toString cfg.dkimKeyBits} \
          --privkey "${privateKey}" > "${publicKey}"
        chmod 0644 "${publicKey}"
        echo "Generated key for domain ${domain} and selector ${cfg.dkimSelector}"
      fi
    '';
in
{
  config = with cfg;
    lib.mkIf enable {
      environment.systemPackages = lib.mkBefore [
        (pkgs.runCommand "rspamc-wrapped"
          {
            nativeBuildInputs = with pkgs; [ makeWrapper ];
          } ''
          makeWrapper ${pkgs.rspamd}/bin/rspamc $out/bin/rspamc \
            --add-flags "-h ${xdgRuntime}/rspamd/worker-controller.sock"
        '')
      ];
      services.rspamd = {
        enable = true;
        inherit debug;
        locals = {
          "milter_headers.conf" = {
            text = ''
              extended_spam_headers = true;
            '';
          };
          "redis.conf" = {
            text = ''
              servers = "${
                if cfg.redis.port == null then
                  cfg.redis.address
                else
                  "${cfg.redis.address}:${toString cfg.redis.port}"
              }";
            '' + (lib.optionalString (cfg.redis.password != null) ''
              password = "${cfg.redis.password}";
            '');
          };
          "classifier-bayes.conf" = {
            text = ''
              cache {
                backend = "redis";
              }
            '';
          };
          "antivirus.conf" = lib.mkIf cfg.virusScanning {
            text = ''
              clamav {
                action = "reject";
                symbol = "CLAM_VIRUS";
                type = "clamav";
                log_clean = true;
                servers = "${xdgRuntime}/clamav/clamd.sock";
                scan_mime_parts = false;
              }
            '';
          };
          "dkim_signing.conf" = {
            text = ''
              enabled = ${lib.boolToString cfg.dkimSigning};
              path = "${cfg.dkimKeyDirectory}/$domain.$selector.key";
              selector = "${cfg.dkimSelector}";
              allow_username_mismatch = true;
            '';
          };
          "dmarc.conf" = {
            text = ''
              ${lib.optionalString cfg.dmarcReporting.enable ''
                reporting {
                  enabled = true;
                  email = "${cfg.dmarcReporting.email}";
                  domain = "${cfg.dmarcReporting.domain}";
                  org_name = "${cfg.dmarcReporting.organizationName}";
                  from_name = "${cfg.dmarcReporting.fromName}";
                  msgid_from = "${cfg.dmarcReporting.domain}";
                  ${
                    lib.optionalString
                    (cfg.dmarcReporting.excludeDomains != [ ]) ''
                      exclude_domains = ${
                        builtins.toJSON cfg.dmarcReporting.excludeDomains
                      };
                    ''
                  }
                }''}
            '';
          };
        };
        workers.rspamd_proxy = {
          type = "rspamd_proxy";
          bindSockets = [{
            socket = "${xdgRuntime}/rspamd/rspamd-milter.sock";
            mode = "0664";
          }];
          count = 1;
          extraConfig = ''
            milter = yes;
            timeout = 120s;
            upstream "local" {
              default = yes;
              self_scan = yes;
            }
          '';
        };
        workers.controller = {
          type = "controller";
          bindSockets = [{
            socket = "${xdgRuntime}/rspamd/worker-controller.sock";
            mode = "0666";
          }];
          includes = [ ];
          extraConfig = ''
            static_dir = "''${WWWDIR}"; # Serve the web UI static assets
          '';
        };
      };
      services.redis.servers.rspamd.enable = lib.mkDefault true;
      systemd.tmpfiles.settings."10-rspamd.conf" = {
        "${cfg.dkimKeyDirectory}" = {
          d = {
            user = rspamdUser;
            group = rspamdGroup;
          };
          Z = {
            user = rspamdUser;
            group = rspamdGroup;
          };
        };
      };
      systemd.services.rspamd = {
        requires = [ "redis-rspamd.service" ]
          ++ (lib.optional cfg.virusScanning "clamav-daemon.service");
        after = [ "redis-rspamd.service" ]
          ++ (lib.optional cfg.virusScanning "clamav-daemon.service");
        serviceConfig = lib.mkMerge [
          {
            SupplementaryGroups =
              [ config.services.redis.servers.rspamd.group ];
          }
          (lib.optionalAttrs cfg.dkimSigning {
            ExecStartPre = map createDkimKeypair cfg.domains;
            ReadWritePaths = [ cfg.dkimKeyDirectory ];
          })
        ];
      };
      systemd.services.rspamd-dmarc-reporter =
        lib.optionalAttrs (cfg.dmarcReporting.enable) {
          script = ''
            ${pkgs.rspamd}/bin/rspamadm dmarc_report $(date -d "yesterday" "+%Y%m%d")
          '';
          serviceConfig = {
            User = "${config.services.rspamd.user}";
            Group = "${config.services.rspamd.group}";
            AmbientCapabilities = [ ];
            CapabilityBoundingSet = "";
            DevicePolicy = "closed";
            IPAddressAllow = "localhost";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateMounts = true;
            PrivateTmp = true;
            PrivateUsers = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            ProtectSystem = "strict";
            RemoveIPC = true;
            RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [ "@system-service" "~@privileged" ];
            UMask = "0077";
          };
        };
      systemd.timers.rspamd-dmarc-reporter =
        lib.optionalAttrs (cfg.dmarcReporting.enable) {
          description = "Daily delivery of aggregated DMARC reports";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = 86400;
            FixedRandomDelay = true;
          };
        };
      systemd.services.postfix = {
        after = [ rspamdSocket ];
        requires = [ rspamdSocket ];
      };
      users.extraUsers.${postfixCfg.user}.extraGroups = [ rspamdCfg.group ];
    };
}



