{ config, pkgs, lib }:
let
  cfg = config.ghost;
in
{
  certificatePath = if cfg.certificateScheme == "manual"
             then cfg.certificateFile
             else if cfg.certificateScheme == "selfsigned"
                  then "${cfg.certificateDirectory}/cert-${cfg.fqdn}.pem"
                  else if cfg.certificateScheme == "acme" || cfg.certificateScheme == "acme-nginx"
                       then "${config.security.acme.certs.${cfg.acmeCertificateName}.directory}/fullchain.pem"
                       else throw "unknown certificate scheme";
  keyPath = if cfg.certificateScheme == "manual"
        then cfg.keyFile
        else if cfg.certificateScheme == "selfsigned"
             then "${cfg.certificateDirectory}/key-${cfg.fqdn}.pem"
              else if cfg.certificateScheme == "acme" || cfg.certificateScheme == "acme-nginx"
                   then "${config.security.acme.certs.${cfg.acmeCertificateName}.directory}/key.pem"
                   else throw "unknown certificate scheme";
  passwordFiles = let
    mkHashFile = name: hash: pkgs.writeText "${builtins.hashString "sha256" name}-password-hash" hash;
  in
    lib.mapAttrs (name: value:
    if value.hashedPasswordFile == null then
      builtins.toString (mkHashFile name value.hashedPassword)
    else value.hashedPasswordFile) cfg.loginAccounts;
  appendLdapBindPwd = {
    name, file, prefix, suffix ? "", passwordFile, destination
  }: pkgs.writeScript "append-ldap-bind-pwd-in-${name}" ''
    #!${pkgs.stdenv.shell}
    set -euo pipefail
    baseDir=$(dirname ${destination})
    if (! test -d "$baseDir"); then
      mkdir -p $baseDir
      chmod 755 $baseDir
    fi
    cat ${file} > ${destination}
    echo -n '${prefix}' >> ${destination}
    cat ${passwordFile} | tr -d '\n' >> ${destination}
    echo -n '${suffix}' >> ${destination}
    chmod 600 ${destination}
  '';
}
