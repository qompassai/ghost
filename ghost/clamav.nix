{ config, lib, ... }:

let
  cfg = config.ghost;
in
{
  config = lib.mkIf (cfg.enable && cfg.virusScanning) {
    services.clamav.daemon = {
      enable = true;
      settings.PhishingScanURLs = "no";
    };
    services.clamav.updater.enable = true;
  };
}
