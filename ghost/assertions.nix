# /qompassai/ghost/ghost/assertions.nix
# Qompass AI Ghost Assertions
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
{ config, lib, ... }: {
  assertions = lib.optionals config.ghost.ldap.enable [
    {
      assertion = config.ghost.loginAccounts == { };
      message =
        "When the LDAP support is enable (ghost.ldap.enable = true), it is not possible to define ghost.loginAccounts";
    }
    {
      assertion = config.ghost.extraVirtualAliases == { };
      message =
        "When the LDAP support is enable (ghost.ldap.enable = true), it is not possible to define ghost.extraVirtualAliases";
    }
  ] ++ lib.optionals
    (config.ghost.enable && config.ghost.certificateScheme != "acme") [{
    assertion = config.ghost.acmeCertificateName == config.ghost.fqdn;
    message = ''
      When the certificate scheme is not 'acme' (ghost.certificateScheme != "acme"), it is not possible to define ghost.acmeCertificateName'';
  }];
}
