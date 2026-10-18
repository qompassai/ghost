# /qompassai/ghost/hosts/mail/hardware-configuration.nix
# Ghost mail host — PLACEHOLDER hardware configuration
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
#
# PLACEHOLDER — this file exists only so the Stage 0 host definition
# evaluates end to end before the instance exists. At provisioning
# (Stage 1) it is REPLACED wholesale by the output of
# `nixos-generate-config` on the real OCI instance; nothing here
# describes real hardware, a real disk, or a real boot setup.
#
# The root device label below is a stand-in chosen to be valid NixOS
# configuration syntax, not a device that exists anywhere.
{ ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos-placeholder";
    fsType = "ext4";
  };
}
