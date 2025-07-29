{ config, pkgs, lib, ... }:
with (import ./common.nix { inherit config pkgs lib; });
let
  inherit (lib.strings) concatStringsSep;
  cfg = config.ghost;
  mergeLookupTables = tables: lib.zipAttrsWith (_: v: lib.flatten v) tables;
  valiases_postfix = mergeLookupTables (lib.flatten (lib.mapAttrsToList
    (name: value:
      let to = name;
      in map (from: { "${from}" = to; }) (value.aliases ++ lib.singleton name))
    cfg.loginAccounts));
  regex_valiases_postfix = mergeLookupTables (lib.flatten (lib.mapAttrsToList
    (name: value:
      let to = name;
      in map (from: { "${from}" = to; }) value.aliasesRegexp)
    cfg.loginAccounts));
  catchAllPostfix = mergeLookupTables (lib.flatten (lib.mapAttrsToList
    (name: value:
      let to = name;
      in map (from: { "@${from}" = to; }) value.catchAll)
    cfg.loginAccounts));
  all_valiases_postfix =
    mergeLookupTables [ valiases_postfix extra_valiases_postfix ];
  attrsToLookupTable = aliases:
    let
      lookupTables = lib.mapAttrsToList (from: to: { "${from}" = to; }) aliases;
    in
    mergeLookupTables lookupTables;
  extra_valiases_postfix = attrsToLookupTable cfg.extraVirtualAliases;
  forwards = attrsToLookupTable cfg.forwards;
  lookupTableToString = attrs:
    let valueToString = value: lib.concatStringsSep ", " value;
    in
    lib.concatStringsSep "\n"
      (lib.mapAttrsToList (name: value: "${name} ${valueToString value}") attrs);
  valiases_file =
    let
      content = lookupTableToString
        (mergeLookupTables [ all_valiases_postfix catchAllPostfix ]);
    in
    builtins.toFile "valias" content;
  regex_valiases_file =
    let content = lookupTableToString regex_valiases_postfix;
    in builtins.toFile "regex_valias" content;
  denied_recipients_postfix =
    (map (acct: "${acct.name} REJECT ${acct.sendOnlyRejectMessage}")
      (lib.filter (acct: acct.sendOnly) (lib.attrValues cfg.loginAccounts)));
  denied_recipients_file = builtins.toFile "denied_recipients"
    (lib.concatStringsSep "\n" denied_recipients_postfix);
  reject_senders_postfix =
    (map (sender: "${sender} REJECT") (cfg.rejectSender));
  reject_senders_file = builtins.toFile "reject_senders"
    (lib.concatStringsSep "\n" (reject_senders_postfix));
  reject_recipients_postfix =
    (map (recipient: "${recipient} REJECT") (cfg.rejectRecipients));
  # rejectRecipients :: [ Path ]
  reject_recipients_file = builtins.toFile "reject_recipients"
    (lib.concatStringsSep "\n" (reject_recipients_postfix));
  vhosts_file = builtins.toFile "vhosts" (concatStringsSep "\n" cfg.domains);
  # vaccounts_file :: Path
  # see
  # https://blog.grimneko.de/2011/12/24/a-bunch-of-tips-for-improving-your-postfix-setup/
  # for details on how this file looks. By using the same file as valiases,
  # every alias is owned (uniquely) by its user.
  # The user's own address is already in all_valiases_postfix.
  vaccounts_file =
    builtins.toFile "vaccounts" (lookupTableToString all_valiases_postfix);
  regex_vaccounts_file = builtins.toFile "regex_vaccounts"
    (lookupTableToString regex_valiases_postfix);
  submissionHeaderCleanupRules =
    pkgs.writeText "submission_header_cleanup_rules" (''
      # Removes sensitive headers from mails handed in via the submission port.
      # See https://thomas-leister.de/mailserver-debian-stretch/
      # Uses "pcre" style regex.
      /^Received:/            IGNORE
      /^X-Originating-IP:/    IGNORE
      /^X-Mailer:/            IGNORE
      /^User-Agent:/          IGNORE
      /^X-Enigmail:/          IGNORE
    '' + lib.optionalString cfg.rewriteMessageId ''
      # Replaces the user submitted hostname with the server's FQDN to hide the
      # user's host or network.
      /^Message-ID:\s+<(.*?)@.*?>/ REPLACE Message-ID: <$1@${cfg.fqdn}>
    '');
  smtpdMilters = [ "unix:/run/rspamd/rspamd-milter.sock" ];
  mappedFile = name: "hash:/var/lib/postfix/conf/${name}";
  mappedRegexFile = name: "pcre:/var/lib/postfix/conf/${name}";
  submissionOptions = {
    smtpd_tls_security_level = "encrypt";
    smtpd_sasl_auth_enable = "yes";
    smtpd_sasl_type = "dovecot";
    smtpd_sasl_path = "/run/dovecot2/auth";
    smtpd_sasl_security_options = "noanonymous";
    smtpd_sasl_local_domain = "$myhostname";
    smtpd_client_restrictions = "permit_sasl_authenticated,reject";
    smtpd_sender_login_maps = "hash:/etc/postfix/vaccounts${
        lib.optionalString cfg.ldap.enable ",ldap:${ldapSenderLoginMapFile}"
      }${
        lib.optionalString (regex_valiases_postfix != { })
        ",pcre:/etc/postfix/regex_vaccounts"
      }";
    smtpd_sender_restrictions = "reject_sender_login_mismatch";
    smtpd_recipient_restrictions =
      "reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_sasl_authenticated,reject";
    cleanup_service_name = "submission-header-cleanup";
  };
  commonLdapConfig = ''
    server_host = ${lib.concatStringsSep " " cfg.ldap.uris}
    start_tls = ${if cfg.ldap.startTls then "yes" else "no"}
    version = 3
    tls_ca_cert_file = ${cfg.ldap.tlsCAFile}
    tls_require_cert = yes
    search_base = ${cfg.ldap.searchBase}
    scope = ${cfg.ldap.searchScope}
    bind = yes
    bind_dn = ${cfg.ldap.bind.dn}
  '';
  ldapSenderLoginMap = pkgs.writeText "ldap-sender-login-map.cf" ''
    ${commonLdapConfig}
    query_filter = ${cfg.ldap.postfix.filter}
    result_attribute = ${cfg.ldap.postfix.mailAttribute}
  '';
  ldapSenderLoginMapFile = "/run/postfix/ldap-sender-login-map.cf";
  appendPwdInSenderLoginMap = appendLdapBindPwd {
    name = "ldap-sender-login-map";
    file = ldapSenderLoginMap;
    prefix = "bind_pw = ";
    passwordFile = cfg.ldap.bind.passwordFile;
    destination = ldapSenderLoginMapFile;
  };
  ldapVirtualMailboxMap = pkgs.writeText "ldap-virtual-mailbox-map.cf" ''
    ${commonLdapConfig}
    query_filter = ${cfg.ldap.postfix.filter}
    result_attribute = ${cfg.ldap.postfix.uidAttribute}
  '';
  ldapVirtualMailboxMapFile = "/run/postfix/ldap-virtual-mailbox-map.cf";
  appendPwdInVirtualMailboxMap = appendLdapBindPwd {
    name = "ldap-virtual-mailbox-map";
    file = ldapVirtualMailboxMap;
    prefix = "bind_pw = ";
    passwordFile = cfg.ldap.bind.passwordFile;
    destination = ldapVirtualMailboxMapFile;
  };
in
{
  config = with cfg;
    lib.mkIf enable {
      systemd.services.postfix-setup = lib.mkIf cfg.ldap.enable {
        preStart = ''
          ${appendPwdInVirtualMailboxMap}
          ${appendPwdInSenderLoginMap}
        '';
        restartTriggers =
          [ appendPwdInVirtualMailboxMap appendPwdInSenderLoginMap ];
      };
      services.postfix = {
        enable = true;
        hostname = "${sendingFqdn}";
        networksStyle = "host";
        mapFiles."valias" = valiases_file;
        mapFiles."regex_valias" = regex_valiases_file;
        mapFiles."vaccounts" = vaccounts_file;
        mapFiles."regex_vaccounts" = regex_vaccounts_file;
        mapFiles."denied_recipients" = denied_recipients_file;
        mapFiles."reject_senders" = reject_senders_file;
        mapFiles."reject_recipients" = reject_recipients_file;
        sslCert = certificatePath;
        sslKey = keyPath;
        enableSubmission = cfg.enableSubmission;
        enableSubmissions = cfg.enableSubmissionSsl;
        virtual = lookupTableToString
          (mergeLookupTables [ all_valiases_postfix catchAllPostfix forwards ]);
        config = {
          mydestination = "";
          recipient_delimiter = cfg.recipientDelimiter;
          smtpd_banner = "${fqdn} ESMTP NO UCE";
          disable_vrfy_command = true;
          message_size_limit = toString cfg.messageSizeLimit;
          virtual_uid_maps = "static:5000";
          virtual_gid_maps = "static:5000";
          virtual_mailbox_base = mailDirectory;
          virtual_mailbox_domains = vhosts_file;
          virtual_mailbox_maps = [ (mappedFile "valias") ]
            ++ lib.optionals (cfg.ldap.enable)
            [ "ldap:${ldapVirtualMailboxMapFile}" ]
            ++ lib.optionals (regex_valiases_postfix != { })
            [ (mappedRegexFile "regex_valias") ];
          virtual_alias_maps = lib.mkAfter
            (lib.optionals (regex_valiases_postfix != { })
              [ (mappedRegexFile "regex_valias") ]);
          virtual_transport = "lmtp:unix:/run/dovecot2/dovecot-lmtp";
          lmtp_destination_recipient_limit = "1";

          # Opportunistic DANE support
          # https://www.postfix.org/postconf.5.html#smtp_tls_security_level
          smtp_dns_support_level = "dnssec";
          smtp_tls_security_level = "dane";
          smtpd_sasl_type = "dovecot";
          smtpd_sasl_path = "/run/dovecot2/auth";
          smtpd_sasl_auth_enable = true;
          smtpd_relay_restrictions = [
            "permit_mynetworks"
            "permit_sasl_authenticated"
            "reject_unauth_destination"
          ];
          # reject selected senders
          smtpd_sender_restrictions =
            [ "check_sender_access ${mappedFile "reject_senders"}" ];

          smtpd_recipient_restrictions = [
            "check_recipient_access ${mappedFile "denied_recipients"}"
            "check_recipient_access ${mappedFile "reject_recipients"}"
            "check_policy_service unix:/run/dovecot2/quota-status"
          ];
          # TLS settings, inspired by https://github.com/jeaye/nix-files
          smtpd_tls_security_level = "may";
          smtpd_tls_protocols =
            "TLSv1.3, TLSv1.2, !TLSv1.1, !TLSv1, !SSLv2, !SSLv3";
          smtp_tls_protocols =
            "TLSv1.3, TLSv1.2, !TLSv1.1, !TLSv1, !SSLv2, !SSLv3";
          smtpd_tls_mandatory_protocols =
            "TLSv1.3, TLSv1.2, !TLSv1.1, !TLSv1, !SSLv2, !SSLv3";
          smtp_tls_mandatory_protocols =
            "TLSv1.3, TLSv1.2, !TLSv1.1, !TLSv1, !SSLv2, !SSLv3";
          smtp_tls_ciphers = "high";
          smtpd_tls_ciphers = "high";
          smtp_tls_mandatory_ciphers = "high";
          smtpd_tls_mandatory_ciphers = "high";
          smtpd_tls_mandatory_exclude_ciphers =
            "MD5, DES, ADH, RC4, PSD, SRP, 3DES, eNULL, aNULL";
          smtpd_tls_exclude_ciphers =
            "MD5, DES, ADH, RC4, PSD, SRP, 3DES, eNULL, aNULL";
          smtp_tls_mandatory_exclude_ciphers =
            "MD5, DES, ADH, RC4, PSD, SRP, 3DES, eNULL, aNULL";
          smtp_tls_exclude_ciphers =
            "MD5, DES, ADH, RC4, PSD, SRP, 3DES, eNULL, aNULL";
          tls_preempt_cipherlist = true;
          smtpd_tls_auth_only = true;
          smtp_tls_loglevel = "1";
          smtpd_tls_loglevel = "1";
          tls_random_source = "dev:/dev/urandom";
          smtpd_milters = smtpdMilters;
          non_smtpd_milters =
            lib.mkIf cfg.dkimSigning [ "unix:/run/rspamd/rspamd-milter.sock" ];
          milter_protocol = "6";
          milter_mail_macros =
            "i {mail_addr} {client_addr} {client_name} {auth_authen}";
          # Fix for https://www.postfix.org/smtp-smuggling.html
          smtpd_forbid_bare_newline = cfg.smtpdForbidBareNewline;
          smtpd_forbid_bare_newline_exclusions = "$mynetworks";
        };
        submissionOptions = submissionOptions;
        submissionsOptions = submissionOptions;
        masterConfig = {
          "lmtp" = {
            # Add headers when delivering, see http://www.postfix.org/smtp.8.html
            # D => Delivered-To, O => X-Original-To, R => Return-Path
            args = [ "flags=O" ];
          };
          "submission-header-cleanup" = {
            type = "unix";
            private = false;
            chroot = false;
            maxproc = 0;
            command = "cleanup";
            args =
              [ "-o" "header_checks=pcre:${submissionHeaderCleanupRules}" ];
          };
        };
      };
    };
}
