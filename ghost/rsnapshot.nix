{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.ghost;
  preexecDefined = cfg.backup.cmdPreexec != null;
  preexecWrapped = pkgs.writeScript "rsnapshot-preexec.sh" ''
    #!${pkgs.stdenv.shell}
    set -e
    ${cfg.backup.cmdPreexec}
  '';
  preexecString = optionalString preexecDefined "cmd_preexec	${preexecWrapped}";
  postexecDefined = cfg.backup.cmdPostexec != null;
  postexecWrapped = pkgs.writeScript "rsnapshot-postexec.sh" ''
    #!${pkgs.stdenv.shell}
    set -e
    ${cfg.backup.cmdPostexec}
  '';
  postexecString = optionalString postexecDefined "cmd_postexec	${postexecWrapped}";
in {
  config = mkIf (cfg.enable && cfg.backup.enable) {
    services.rsnapshot = {
      enable = true;
      cronIntervals = cfg.backup.cronIntervals;
      extraConfig = ''
        ${preexecString}
        ${postexecString}
        snapshot_root	${cfg.backup.snapshotRoot}/
        retain	hourly	${toString cfg.backup.retain.hourly}
        retain	daily	${toString cfg.backup.retain.daily}
        retain	weekly	${toString cfg.backup.retain.weekly}
        backup	${cfg.mailDirectory}/	localhost/
      '';
    };
  };
}
