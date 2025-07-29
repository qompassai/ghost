{ config, pkgs, lib, ... }:
let cfg = config.ghost;
in
{
  config = with cfg;
    lib.mkIf enable {
      environment.systemPackages = with pkgs;
        [ dovecot openssh postfix rspamd ]
        ++ (if certificateScheme == "selfsigned" then [ openssl ] else [ ]);
    };
}
