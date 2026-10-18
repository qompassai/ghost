# /qompassai/ghost/hosts/mail/configuration.nix
# Ghost mail host — separate NixOS instance for qompass.ai mail
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
#
# STAGE 0 SKELETON — NOT DEPLOYED. Authored 2026-10-17 under Matt's
# "begin ghost zero" order as additive preparation only. Nothing in
# this directory has been built, deployed, or pointed DNS at.
#
# This file is the host definition for the separate mail instance
# (deployment route decided 2026-10-15: a dedicated NixOS instance,
# not the web box). It is composed by the flake output
# `nixosConfigurations.mail` together with:
#
#   - the Ghost module itself (../../default.nix), and
#   - examples/qompass-ai.nix, which carries the entire mail policy:
#     the map@ mailbox, the abuse/legal/mail/postmaster/security
#     aliases, catch-all OFF, the send-only automation login granted
#     send-as map@ only, DKIM selector "ghost" (RSA 2048), ACME TLS.
#
# This file therefore contains ONLY host-level concerns: identity,
# operator access, and the secrets plumbing the policy file names.
# Do not restate mail policy here; change examples/qompass-ai.nix and
# let tests/qompass.nix keep proving it in a VM.
#
# Provisioning (Stage 1, Matt present) replaces
# ./hardware-configuration.nix with nixos-generate-config output for
# the real instance, creates the sops secrets file on the instance,
# and adds the operator's SSH public key below.
{ config, lib, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # Host identity. The Ghost module's own fqdn (mail.qompass.ai) is
  # set in examples/qompass-ai.nix and governs mail behaviour; this
  # is the OS-level hostname.
  networking.hostName = "mail";
  networking.domain = "qompass.ai";

  # The instance's public IP comes from OCI (DHCP on the VNIC, with
  # the address reserved in the tenancy so it never changes). The
  # Ghost module opens the mail ports itself (ghost.openFirewall
  # defaults to true); no extra ports are opened here. SSH is the
  # only host-level service.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  # TODO(stage1): operator public key, added at provisioning. No key
  # material is ever committed to this repo.
  users.users.root.openssh.authorizedKeys.keys = [ ];

  # ACME terms + contact. The production policy selects the
  # module's acme-nginx certificate scheme, and NixOS requires the
  # host (not the module) to accept the CA's terms and name a
  # registration contact. postmaster@ is an alias of the operator
  # mailbox, so expiry/issuance mail lands with Matt. (The VM test
  # never needs this: it overrides the scheme to selfsigned, which
  # is why the requirement only surfaces in a real host eval.)
  security.acme = {
    acceptTerms = true;
    defaults.email = "postmaster@qompass.ai";
  };

  # Secrets plumbing. examples/qompass-ai.nix reads the two
  # hashed-password files from /run/secrets/; sops-nix renders them
  # there from the operator's encrypted secrets file. That file is
  # created ON the instance at Stage 1 and is never committed (the
  # repo's .gitignore already excludes local secret material).
  # The pinned sops-nix requires defaultSopsFile to be SET whenever
  # secrets are declared (it is evaluated as part of the system
  # closure), so the skeleton names the instance-local path now.
  # The file itself is created on the instance at provisioning and
  # never enters this repo or the Nix store's source tree.
  sops.defaultSopsFile = "/var/lib/ghost/secrets.yaml";
  # The secrets file does not exist yet, so sops-nix's eval-time
  # validation cannot pass in the skeleton. It is disabled here and
  # ONLY here: at provisioning, once the real file is in place, this
  # line comes out and validation returns to its default (true).
  sops.validateSopsFiles = false;
  sops.secrets = {
    "ghost-automation-passwordhash" = { };
    "ghost-map-passwordhash" = { };
  };

  # Mail hosts keep their own clock honest: DKIM/DMARC evaluation and
  # queue retries all assume sane time. UTC avoids DST surprises in
  # logs and reports.
  time.timeZone = "UTC";

  # Pinned release line for the deployment (cutover packet, Stage 1:
  # "deploy from the pinned 25.05 line"). The flake composes this
  # host from nixpkgs-25_05 to match.
  system.stateVersion = "25.05";
}
