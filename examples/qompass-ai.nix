# /qompassai/ghost/examples/qompass-ai.nix
# Qompass AI Ghost Example — qompass.ai production mail configuration
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
#
# The qompass.ai mail deployment, expressed in Ghost's configuration
# vocabulary. This file is the production intent: it is imported by the
# mail host's NixOS configuration at deploy time and by
# tests/qompass.nix, which overrides only the credential files, the
# certificate scheme, and the DNS resolver so the identical address and
# identity policy is exercised in a VM.
#
# Address design:
#   - One human mailbox: map@qompass.ai.
#   - Role addresses are aliases of that mailbox (an account alias both
#     receives for the mailbox and grants the owner send-as rights via
#     the Postfix sender-login map; see ghost/postfix.nix vaccounts).
#   - Catch-all is OFF (the loginAccounts catchAll list stays empty):
#     unknown local parts are rejected at SMTP time instead of being
#     silently collected, so typos and dictionary probes get a 5xx and
#     no mailbox fills with mail nobody asked for.
#
# Identity design:
#   - Matt's login (map@qompass.ai) may submit as itself and as every
#     alias it owns.
#   - The automation credential (automation@qompass.ai) is a separate
#     send-only login granted exactly one sender identity,
#     map@qompass.ai, via extraSenderLogins. It owns no mailbox content
#     and cannot submit as any other address; a leaked automation
#     credential can be revoked without touching the human login.
#
# Secrets: this file names credential SOURCES only. At deploy time the
# hashed-password files are provisioned under /run/secrets/ from the
# operator's password store (see the deployment notes in the Phase 0
# decision packet; sops-nix is the recommended renderer, and the flake
# already carries it as an input). No password, hash, or key material
# is ever committed.
#
# DKIM: selector "ghost", RSA 2048. Ed25519 is the module default, but
# some large verifiers have historically ignored ed25519-only
# signatures; RSA 2048 is the conservative choice for a new domain
# building sender reputation. The matching DNS TXT record is generated
# by rspamadm at first activation and published per the packet's DNS
# drafts.
{ ... }:
{
  ghost = {
    enable = true;
    fqdn = "mail.qompass.ai";
    domains = [ "qompass.ai" ];

    # TLS for the mail FQDN via the module's ACME/nginx path; the
    # mail host owns mail.qompass.ai outright, so it may hold :80/:443
    # for challenges. (The VM test overrides this to "selfsigned".)
    certificateScheme = "acme-nginx";

    # Absolute path: the module default is an unexpanded "$HOME/..."
    # string, unusable by the root-run keygen service.
    dkimKeyDirectory = "/var/lib/ghost/dkim";
    dkimSelector = "ghost";
    dkimKeyType = "rsa";
    dkimKeyBits = 2048;

    loginAccounts = {
      "automation@qompass.ai" = {
        hashedPasswordFile = "/run/secrets/ghost-automation-passwordhash";
        sendOnly = true;
      };
      "map@qompass.ai" = {
        hashedPasswordFile = "/run/secrets/ghost-map-passwordhash";
        aliases = [
          "abuse@qompass.ai"
          "legal@qompass.ai"
          "mail@qompass.ai"
          "postmaster@qompass.ai"
          "security@qompass.ai"
        ];
        # Catch-all OFF: see the header note. The empty list is the
        # shipped default, stated explicitly so the policy is visible
        # in review.
        catchAll = [ ];
      };
    };

    # The automation login may submit as map@qompass.ai — and only as
    # map@qompass.ai. This extends the sender-login map without
    # creating a virtual alias, so mail addressed to map@ is never
    # delivered to the automation account.
    extraSenderLogins = {
      "map@qompass.ai" = "automation@qompass.ai";
    };
  };
}
