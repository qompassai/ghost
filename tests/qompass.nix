# /qompassai/ghost/tests/qompass.nix
# Qompass AI Ghost Test — qompass.ai address and identity policy
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
#
# Exercises the production configuration in examples/qompass-ai.nix in
# a VM, overriding only credential files, the certificate scheme, and
# the DNS resolver, and adding two test-only fixtures (an archive
# mailbox and a fan-out alias) that the production config deliberately
# does not carry.
#
# Validation half:
#   - external mail to an alias (security@) lands in map@'s mailbox
#   - a one-to-many alias (crew@) lands in every target mailbox
#   - the human login can submit as a granted alias (security@)
#   - the automation login can submit as map@, and the message is
#     DKIM-signed with selector "ghost"
# Adversarial half:
#   - an unknown local part is rejected at SMTP time (catch-all off)
#   - the human login cannot submit as another account's address
#   - the automation login cannot submit as security@
#   - unauthenticated submission is refused
{ pkgs, lib, ... }:
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
  passwordFile = pkgs.writeText "password" "my-password";
  automationPasswordFile = pkgs.writeText "automation-password" "automation-password";

  # Minimal SMTP probe: exits 0 when the server accepts the message,
  # 1 on any refusal. Used with machine.succeed for the validation
  # half and machine.fail for the adversarial half.
  smtpProbe = pkgs.writeScriptBin "smtp-probe" ''
    #!${pkgs.python3}/bin/python
    import argparse, smtplib, ssl, sys
    from email.message import EmailMessage

    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--from", dest="sender", required=True)
    p.add_argument("--to", dest="recipient", required=True)
    p.add_argument("--subject", required=True)
    p.add_argument("--user")
    p.add_argument("--password-file")
    p.add_argument("--starttls", action="store_true")
    a = p.parse_args()

    msg = EmailMessage()
    msg["From"] = a.sender
    msg["To"] = a.recipient
    msg["Subject"] = a.subject
    msg.set_content("ghost qompass policy probe: " + a.subject)
    try:
        with smtplib.SMTP("localhost", a.port, timeout=20) as s:
            if a.starttls:
                s.starttls(context=ssl._create_unverified_context())
            if a.user:
                with open(a.password_file) as f:
                    s.login(a.user, f.read().strip())
            s.send_message(msg)
    except Exception as e:
        print("PROBE REFUSED:", e)
        sys.exit(1)
    print("PROBE ACCEPTED")
  '';

  # IMAP read-back: exits 0 when a message with the given subject is
  # present in the account's INBOX (retrying while LMTP delivers),
  # printing its headers so the test can grep for DKIM-Signature.
  imapFetch = pkgs.writeScriptBin "imap-fetch" ''
    #!${pkgs.python3}/bin/python
    import argparse, imaplib, ssl, sys, time

    p = argparse.ArgumentParser()
    p.add_argument("--user", required=True)
    p.add_argument("--password-file", required=True)
    p.add_argument("--subject", required=True)
    a = p.parse_args()

    with open(a.password_file) as f:
        password = f.read().strip()
    ctx = ssl._create_unverified_context()
    for _ in range(20):
        try:
            with imaplib.IMAP4_SSL("localhost", 993, ssl_context=ctx) as imap:
                imap.login(a.user, password)
                imap.select("INBOX")
                status, data = imap.search(None, "SUBJECT", '"%s"' % a.subject)
                ids = data[0].split()
                if status == "OK" and ids:
                    status, msg = imap.fetch(ids[-1], "(RFC822.HEADER)")
                    print(msg[0][1].decode("utf-8", "replace"))
                    sys.exit(0)
        except Exception as e:
            print("fetch retry:", e)
        time.sleep(3)
    print("MESSAGE NOT FOUND:", a.subject)
    sys.exit(1)
  '';
in
{
  name = "qompass";
  nodes = {
    machine =
      { pkgs, ... }:
      {
        imports = [
          ./../default.nix
          ./../examples/qompass-ai.nix
          ./lib/config.nix
        ];
        virtualisation.memorySize = 2048;
        environment.systemPackages = [
          smtpProbe
          imapFetch
          (pkgs.writeScriptBin "mail-check" ''
            ${pkgs.python3}/bin/python ${../scripts/mail-check.py} $@
          '')
        ];
        ghost = {
          certificateScheme = lib.mkForce "selfsigned";
          localDnsResolver = false;
          loginAccounts = {
            "map@qompass.ai".hashedPasswordFile =
              lib.mkForce (hashPassword "my-password");
            "automation@qompass.ai".hashedPasswordFile =
              lib.mkForce (hashPassword "automation-password");
            # Test-only second mailbox: proves one-to-many fan-out.
            "archive@qompass.ai" = {
              hashedPasswordFile = hashPassword "my-password";
            };
          };
          # Test-only fan-out alias (production carries none).
          extraVirtualAliases = {
            "crew@qompass.ai" = [
              "archive@qompass.ai"
              "map@qompass.ai"
            ];
          };
        };
      };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_open_port(25)
    machine.wait_for_open_port(587)
    machine.wait_for_open_port(993)

    # --- Validation: alias expansion (security@ -> map@) ---
    machine.succeed(
        "smtp-probe --port 25 --from alice@example.org "
        "--to security@qompass.ai --subject alias-security")
    machine.succeed(
        "imap-fetch --user map@qompass.ai --password-file ${passwordFile} "
        "--subject alias-security")

    # --- Validation: one-to-many fan-out (crew@ -> map@ + archive@) ---
    machine.succeed(
        "smtp-probe --port 25 --from alice@example.org "
        "--to crew@qompass.ai --subject fanout-crew")
    machine.succeed(
        "imap-fetch --user map@qompass.ai --password-file ${passwordFile} "
        "--subject fanout-crew")
    machine.succeed(
        "imap-fetch --user archive@qompass.ai --password-file ${passwordFile} "
        "--subject fanout-crew")

    # --- Validation: human login submits as a granted alias ---
    machine.succeed(
        "smtp-probe --port 587 --starttls --user map@qompass.ai "
        "--password-file ${passwordFile} --from security@qompass.ai "
        "--to map@qompass.ai --subject sendas-security")
    machine.succeed(
        "imap-fetch --user map@qompass.ai --password-file ${passwordFile} "
        "--subject sendas-security")

    # --- Validation: automation login submits as map@, DKIM-signed ---
    machine.succeed(
        "smtp-probe --port 587 --starttls --user automation@qompass.ai "
        "--password-file ${automationPasswordFile} --from map@qompass.ai "
        "--to map@qompass.ai --subject automation-map")
    machine.succeed(
        "imap-fetch --user map@qompass.ai --password-file ${passwordFile} "
        "--subject automation-map | grep -i '^DKIM-Signature:'")
    machine.succeed(
        "imap-fetch --user map@qompass.ai --password-file ${passwordFile} "
        "--subject automation-map | grep -i 's=ghost'")

    # --- Adversarial: unknown local part rejected (catch-all off) ---
    machine.fail(
        "smtp-probe --port 25 --from alice@example.org "
        "--to nosuch@qompass.ai --subject should-not-arrive")

    # --- Adversarial: human login cannot submit as another's address ---
    machine.fail(
        "smtp-probe --port 587 --starttls --user map@qompass.ai "
        "--password-file ${passwordFile} --from automation@qompass.ai "
        "--to map@qompass.ai --subject mismatch-human")

    # --- Adversarial: automation login cannot submit as security@ ---
    machine.fail(
        "smtp-probe --port 587 --starttls --user automation@qompass.ai "
        "--password-file ${automationPasswordFile} "
        "--from security@qompass.ai --to map@qompass.ai "
        "--subject mismatch-automation")

    # --- Adversarial: unauthenticated submission refused ---
    machine.fail(
        "smtp-probe --port 587 --starttls --from map@qompass.ai "
        "--to map@qompass.ai --subject unauthenticated")
  '';
}
