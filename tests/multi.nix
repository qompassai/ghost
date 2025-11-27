# /qompassai/ghost/tests/multi.nix
# Qompass AI Ghost Multi-domain Test
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{
  pkgs,
  ...
}:

let
  hashPassword =
    password:
    pkgs.runCommand "password-${password}-hashed"
      {
        buildInputs = [ pkgs.mkpasswd ];
        inherit password;
      }
      ''
        mkpasswd -sm bcrypt <<<"$password" > $out
      '';

  password = pkgs.writeText "password" "password";
  domainGenerator =
    domain:
    { pkgs, ... }:
    {
      imports = [
        ../default.nix
        ./lib/config.nix
      ];
      environment.systemPackages = with pkgs; [ netcat ];
      virtualisation.memorySize = 1024;
      ghost = {
        enable = true;
        fqdn = "mail.${domain}";
        domains = [ domain ];
        localDnsResolver = false;
        loginAccounts = {
          "user@${domain}" = {
            hashedPasswordFile = hashPassword "password";
          };
        };
        enableImap = true;
        enableImapSsl = true;
      };
      services.dnsmasq = {
        enable = true;
        settings.mx-host = [
          "domain1.com,domain1,10"
          "domain2.com,domain2,10"
        ];
      };
    };

in
{
  name = "multi";
  nodes = {
    domain1 =
      { ... }:
      {
        imports = [
          ../default.nix
          (domainGenerator "domain1.com")
        ];
        ghost.forwards = {
          "non-local@domain1.com" = [
            "user@domain2.com"
            "user@domain1.com"
          ];
          "non@domain1.com" = [
            "user@domain2.com"
            "user@domain1.com"
          ];
        };
      };
    domain2 = domainGenerator "domain2.com";
    client =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          (pkgs.writeScriptBin "mail-check" ''
            ${pkgs.python3}/bin/python ${../scripts/mail-check.py} $@
          '')
        ];
      };
  };
  testScript = ''
    start_all()

    domain1.wait_for_unit("multi-user.target")
    domain2.wait_for_unit("multi-user.target")

    # TODO put this blocking into the systemd units?
    domain1.wait_until_succeeds(
        "set +e; timeout 1 nc -U /run/rspamd/rspamd-milter.sock < /dev/null; [ $? -eq 124 ]"
    )
    domain2.wait_until_succeeds(
        "set +e; timeout 1 nc -U /run/rspamd/rspamd-milter.sock < /dev/null; [ $? -eq 124 ]"
    )

    # user@domain1.com sends a mail to user@domain2.com
    client.succeed(
        "mail-check send-and-read --smtp-port 587 --smtp-starttls --smtp-host domain1 --from-addr user@domain1.com --imap-host domain2 --to-addr user@domain2.com --src-password-file ${password} --dst-password-file ${password} --ignore-dkim-spf"
    )

    # Send a mail to the address forwarded and check it is in the recipient mailbox
    client.succeed(
        "mail-check send-and-read --smtp-port 587 --smtp-starttls --smtp-host domain1 --from-addr user@domain1.com --imap-host domain2 --to-addr non-local@domain1.com --imap-username user@domain2.com --src-password-file ${password} --dst-password-file ${password} --ignore-dkim-spf"
    )
  '';
}

