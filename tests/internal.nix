# internal.nix
# Qompass AI - [Add description here]
# Copyright (C) 2025 Qompass AI, All rights reserved
# ----------------------------------------
{
  pkgs,
  ...
}:
let
  sendMail = pkgs.writeTextFile {
    "name" = "send-mail-to-send-only-account";
    "text" = ''
      EHLO mail.example.com
      MAIL FROM: none@example.com
      RCPT TO: send-only@example.com
      QUIT
    '';
  };
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
  hashedPasswordFile = hashPassword "my-password";
  passwordFile = pkgs.writeText "password" "my-password";
in
{
  name = "internal";
  nodes = {
    machine =
      { pkgs, ... }:
      {
        imports = [
          ./../default.nix
          ./lib/config.nix
        ];
        virtualisation.memorySize = 1024;
        environment.systemPackages =
          [
            (pkgs.writeScriptBin "mail-check" ''
              ${pkgs.python3}/bin/python ${../scripts/mail-check.py} $@
            '')
          ]
          ++ (with pkgs; [
            curl
            openssl
            netcat
          ]);
        ghost = {
          enable = true;
          fqdn = "mail.example.com";
          domains = [
            "example.com"
            "domain.com"
          ];
          localDnsResolver = false;

          loginAccounts = {
            "user1@example.com" = {
              hashedPasswordFile = hashedPasswordFile;
            };
            "user2@example.com" = {
              hashedPasswordFile = hashedPasswordFile;
              aliasesRegexp = [ ''/^user2.*@domain\.com$/'' ];
            };
            "send-only@example.com" = {
              hashedPasswordFile = hashPassword "send-only";
              sendOnly = true;
            };
          };
          forwards = {
            "user2@example.com" = "user1@example.com";
          };
          vmailGroupName = "vmail";
          vmailUID = 5000;
          indexDir = "/var/lib/dovecot/indices";
          enableImap = false;
        };
      };
  };
  testScript =
    {
      nodes,
      ...
    }:
    ''
      machine.start()
      machine.wait_for_unit("multi-user.target")
          machine.succeed(
              " ".join(
                  [
                      "mail-check send-and-read",
                      "--smtp-port 587",
                      "--smtp-starttls",
                      "--smtp-host localhost",
                      "--imap-host localhost",
                      "--imap-username user1@example.com",
                      "--from-addr user1@example.com",
                      "--to-addr user2@example.com",
                      "--src-password-file ${passwordFile}",
                      "--dst-password-file ${passwordFile}",
                      "--ignore-dkim-spf",
                  ]
              )
          )
          machine.succeed(
              " ".join(
                  [
                      "mail-check send-and-read",
                      "--smtp-port 587",
                      "--smtp-starttls",
                      "--smtp-host localhost",
                      "--imap-host localhost",
                      "--imap-username user2@example.com",
                      "--from-addr user1@example.com",
                      "--to-addr user2@example.com",
                      "--src-password-file ${passwordFile}",
                      "--dst-password-file ${passwordFile}",
                      "--ignore-dkim-spf",
                  ]
              )
          )

      with subtest("regex email alias are received"):
          machine.succeed(
              " ".join(
                  [
                      "mail-check send-and-read",
                      "--smtp-port 587",
                      "--smtp-starttls",
                      "--smtp-host localhost",
                      "--imap-host localhost",
                      "--imap-username user2@example.com",
                      "--from-addr user1@example.com",
                      "--to-addr user2-regex-alias@domain.com",
                      "--src-password-file ${passwordFile}",
                      "--dst-password-file ${passwordFile}",
                      "--ignore-dkim-spf",
                  ]
              )
          )
      with subtest("user can send from regex email alias"):
          # A mail sent from user2-regex-alias@domain.com, using user2@example.com credentials is received
          machine.succeed(
              " ".join(
                  [
                      "mail-check send-and-read",
                      "--smtp-port 587",
                      "--smtp-starttls",
                      "--smtp-host localhost",
                      "--imap-host localhost",
                      "--smtp-username user2@example.com",
                      "--from-addr user2-regex-alias@domain.com",
                      "--to-addr user1@example.com",
                      "--src-password-file ${passwordFile}",
                      "--dst-password-file ${passwordFile}",
                      "--ignore-dkim-spf",
                  ]
              )
          )
      with subtest("vmail gid is set correctly"):
          machine.succeed("getent group vmail | grep 5000")
      with subtest("Check dovecot maildir and index locations"):
          # If these paths change we need a migration
          machine.succeed("doveadm user -f home user1@example.com | grep ${nodes.machine.ghost.mailDirectory}/example.com/user1")
          machine.succeed("doveadm user -f mail user1@example.com | grep 'maildir:~/mail:INDEX=${nodes.machine.ghost.indexDir}/example.com/user1'")
      with subtest("mail to send only accounts is rejected"):
          machine.wait_for_open_port(25)
          # TODO put this blocking into the systemd units
          machine.wait_until_succeeds(
              "set +e; timeout 1 nc -U /run/rspamd/rspamd-milter.sock < /dev/null; [ $? -eq 124 ]"
          )
          machine.succeed(
              "cat ${sendMail} | nc localhost 25 | grep -q '554 5.5.0 Error'"
          )
      with subtest("rspamd controller serves web ui"):
          machine.succeed(
              "set +o pipefail; curl --unix-socket /run/rspamd/worker-controller.sock http://localhost/ | grep -q '<body>'"
          )
      with subtest("imap port 143 is closed and imaps is serving SSL"):
          machine.wait_for_closed_port(143)
          machine.wait_for_open_port(993)
          machine.succeed(
              "echo | openssl s_client -connect localhost:993 | grep 'New, TLS'"
          )
    '';
}
