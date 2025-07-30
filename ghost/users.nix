# /qompassai/ghost/ghost/users.nix
# Qompass AI Ghost Users
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{ config, pkgs, lib, ... }:
with config.ghost;
let
  vmail_user = {
    name = vmailUserName;
    isSystemUser = true;
    uid = vmailUID;
    home = mailDirectory;
    createHome = true;
    group = vmailGroupName;
  };
  virtualMailUsersActivationScript =
    pkgs.writeScript "activate-virtual-mail-users" ''
      #!${pkgs.stdenv.shell}
      set -euo pipefail
      # Prevent world-readable paths, even temporarily.
      umask 007
      # Create directory to store user sieve scripts if it doesn't exist
      if (! test -d "${sieveDirectory}"); then
        mkdir "${sieveDirectory}"
        chown "${vmailUserName}:${vmailGroupName}" "${sieveDirectory}"
        chmod 770 "${sieveDirectory}"
      fi
      # Copy user's sieve script to the correct location (if it exists).  If it
      # is null, remove the file.
      ${lib.concatMapStringsSep "\n" ({ name, sieveScript }:
        if lib.isString sieveScript then ''
          if (! test -d "${sieveDirectory}/${name}"); then
            mkdir -p "${sieveDirectory}/${name}"
            chown "${vmailUserName}:${vmailGroupName}" "${sieveDirectory}/${name}"
            chmod 770 "${sieveDirectory}/${name}"
          fi
          cat << 'EOF' > "${sieveDirectory}/${name}/default.sieve"
          ${sieveScript}
          EOF
          chown "${vmailUserName}:${vmailGroupName}" "${sieveDirectory}/${name}/default.sieve"
        '' else ''
          if (test -f "${sieveDirectory}/${name}/default.sieve"); then
            rm "${sieveDirectory}/${name}/default.sieve"
          fi
          if (test -f "${sieveDirectory}/${name}.svbin"); then
            rm "${sieveDirectory}/${name}/default.svbin"
          fi
        '') (map (user: { inherit (user) name sieveScript; })
          (lib.attrValues loginAccounts))}
    '';
in
{
  config = lib.mkIf enable {
    assertions = (map
      (acct: {
        assertion =
          (acct.hashedPassword != null || acct.hashedPasswordFile != null);
        message =
          "${acct.name} must provide either a hashed password or a password hash file";
      })
      (lib.attrValues loginAccounts));
    warnings = (map
      (acct:
        "${acct.name} specifies both a password hash and hash file; hash file will be used")
      (lib.filter
        (acct: (acct.hashedPassword != null && acct.hashedPasswordFile != null))
        (lib.attrValues loginAccounts)));
    users.groups = { "${vmailGroupName}" = { gid = vmailUID; }; };
    users.users = { "${vmail_user.name}" = lib.mkForce vmail_user; };
    systemd.services.activate-virtual-mail-users = {
      wantedBy = [ "multi-user.target" ];
      before = [ "dovecot2.service" ];
      serviceConfig = { ExecStart = virtualMailUsersActivationScript; };
      enable = true;
    };
  };
}
