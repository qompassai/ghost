{ config, lib, ... }:
let cfg = config.ghost;
in
{
  config = lib.mkIf (cfg.enable && cfg.localDnsResolver) {
    services.kresd.enable = true;
  };
}
