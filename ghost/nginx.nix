{ config, pkgs, lib, ... }:
with (import ./common.nix { inherit config lib pkgs; });
let
  cfg = config.ghost;
in
{
  config = lib.mkIf (cfg.enable && (cfg.certificateScheme == "acme" || cfg.certificateScheme == "acme-nginx")) {
    services.nginx = lib.mkIf (cfg.certificateScheme == "acme-nginx") {
      enable = true;
      virtualHosts."${cfg.fqdn}" = {
        serverName = cfg.fqdn;
        serverAliases = cfg.certificateDomains;
        forceSSL = true;
        enableACME = true;
      };
    };
    security.acme.certs."${cfg.acmeCertificateName}".reloadServices = [
      "postfix.service"
      "dovecot2.service"
    ];
  };
}
