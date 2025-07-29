{ options, config, pkgs, lib, ... }:
with (import ./common.nix { inherit config pkgs lib; });
let
  cfg = config.ghost;
  passwdDir = "/run/dovecot2";
  passwdFile = "${passwdDir}/passwd";
  userdbFile = "${passwdDir}/userdb";
  # This file contains the ldap bind password
  ldapConfFile = "${passwdDir}/dovecot-ldap.conf.ext";
  boolToYesNo = x: if x then "yes" else "no";
  listToLine = lib.concatStringsSep " ";
  listToMultiAttrs = keyPrefix: attrs:
    lib.listToAttrs (lib.imap1
      (n: x: {
        name = "${keyPrefix}${if n == 1 then "" else toString n}";
        value = x;
      })
      attrs);
  maildirLayoutAppendix = lib.optionalString cfg.useFsLayout ":LAYOUT=fs";
  maildirUTF8FolderNames = lib.optionalString cfg.useUTF8FolderNames ":UTF-8";
  dovecotMaildir =
    "maildir:${cfg.mailDirectory}/%{domain}/%{username}${maildirLayoutAppendix}${maildirUTF8FolderNames}"
    + (lib.optionalString (cfg.indexDir != null)
      ":INDEX=${cfg.indexDir}/%{domain}/%{username}");
  postfixCfg = config.services.postfix;
  ldapConfig = pkgs.writeTextFile {
    name = "dovecot-ldap.conf.ext.template";
    text = ''
      ldap_version = 3
      uris = ${lib.concatStringsSep " " cfg.ldap.uris}
      ${lib.optionalString cfg.ldap.startTls ''
        tls = yes
      ''}
      tls_require_cert = hard
      tls_ca_cert_file = ${cfg.ldap.tlsCAFile}
      dn = ${cfg.ldap.bind.dn}
      sasl_bind = no
      auth_bind = yes
      base = ${cfg.ldap.searchBase}
      scope = ${mkLdapSearchScope cfg.ldap.searchScope}
      ${lib.optionalString (cfg.ldap.dovecot.userAttrs != null) ''
        user_attrs = ${cfg.ldap.dovecot.userAttrs}
      ''}
      user_filter = ${cfg.ldap.dovecot.userFilter}
      ${lib.optionalString (cfg.ldap.dovecot.passAttrs != "") ''
        pass_attrs = ${cfg.ldap.dovecot.passAttrs}
      ''}
      pass_filter = ${cfg.ldap.dovecot.passFilter}
    '';
  };
  setPwdInLdapConfFile = appendLdapBindPwd {
    name = "ldap-conf-file";
    file = ldapConfig;
    prefix = ''dnpass = "'';
    suffix = ''"'';
    passwordFile = cfg.ldap.bind.passwordFile;
    destination = ldapConfFile;
  };
  genPasswdScript = pkgs.writeScript "generate-password-file" ''
    #!${pkgs.stdenv.shell}
    set -euo pipefail
    if (! test -d "${passwdDir}"); then
      mkdir "${passwdDir}"
      chmod 755 "${passwdDir}"
    fi
    # Prevent world-readable password files, even temporarily.
    umask 077
    for f in ${
      builtins.toString
      (lib.mapAttrsToList (name: _: passwordFiles."${name}") cfg.loginAccounts)
    }; do
      if [ ! -f "$f" ]; then
        echo "Expected password hash file $f does not exist!"
        exit 1
      fi
    done
    cat <<EOF > ${passwdFile}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (name: _: "${name}:${"$(head -n 1 ${passwordFiles."${name}"})"}::::::")
      cfg.loginAccounts)}
    EOF
    cat <<EOF > ${userdbFile}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value:
      "${name}:::::::" + lib.optionalString (value.quota != null)
      "userdb_quota_rule=*:storage=${value.quota}") cfg.loginAccounts)}
    EOF
  '';
  junkMailboxes = builtins.attrNames
    (lib.filterAttrs (_: v: v ? "specialUse" && v.specialUse == "Junk")
      cfg.mailboxes);
  junkMailboxNumber = builtins.length junkMailboxes;
  junkMailboxName =
    if junkMailboxNumber == 1 then builtins.elemAt junkMailboxes 0 else "";
  mkLdapSearchScope = scope:
    (if scope == "sub" then
      "subtree"
    else if scope == "one" then
      "onelevel"
    else
      scope);
  dovecotModules = [ pkgs.dovecot_pigeonhole ]
    ++ lib.optional cfg.fullTextSearch.enable pkgs.dovecot-fts-flatcurve;
  # Remove and assume `false` after NixOS 25.05
  haveDovecotModulesOption = options.services.dovecot2 ? "modules"
    && (options.services.dovecot2.modules.visible or true);
  ftsPluginSettings = {
    fts = "flatcurve";
    fts_languages = listToLine cfg.fullTextSearch.languages;
    fts_tokenizers = listToLine [ "generic" "email-address" ];
    fts_tokenizer_email_address =
      "maxlen=100"; # default 254 too large for Xapian
    fts_flatcurve_substring_search =
      boolToYesNo cfg.fullTextSearch.substringSearch;
    fts_filters = listToLine cfg.fullTextSearch.filters;
    fts_header_excludes = listToLine cfg.fullTextSearch.headerExcludes;
    fts_autoindex = boolToYesNo cfg.fullTextSearch.autoIndex;
    fts_enforced = cfg.fullTextSearch.enforced;
  } // (listToMultiAttrs "fts_autoindex_exclude"
    cfg.fullTextSearch.autoIndexExclude);
in
{
  config = with cfg;
    lib.mkIf enable {
      assertions = [{
        assertion = junkMailboxNumber == 1;
        message =
          "Qompass AI Ghost requires exactly one dovecot mailbox with the 'special use' flag set to 'Junk' (${
            builtins.toString junkMailboxNumber
          } have been found)";
      }];
      warnings = (lib.optional
        ((builtins.length cfg.fullTextSearch.languages > 1)
          && (builtins.elem "stopwords" cfg.fullTextSearch.filters)) ''
        Using stopwords in `ghost.fullTextSearch.filters` with multiple
        languages in `ghost.fullTextSearch.languages` configured WILL
        cause some searches to fail.

        The recommended solution is to NOT use the stopword filter when
        multiple languages are present in the configuration.
      '');

      # for sieve-test. Shelling it in on demand usually doesnt' work, as it reads
      # the global config and tries to open shared libraries configured in there,
      # which are usually not compatible.
      environment.systemPackages = [ pkgs.dovecot_pigeonhole ]
        ++ lib.optionals (!haveDovecotModulesOption) dovecotModules;

      # For compatibility with python imaplib
      environment.etc = lib.mkIf (!haveDovecotModulesOption) {
        "dovecot/modules".source = "/run/current-system/sw/lib/dovecot/modules";
      };
      services.dovecot2 = lib.mkMerge [
        {
          enable = true;
          enableImap = enableImap || enableImapSsl;
          enablePop3 = enablePop3 || enablePop3Ssl;
          enablePAM = false;
          enableQuota = true;
          mailGroup = vmailGroupName;
          mailUser = vmailUserName;
          mailLocation = dovecotMaildir;
          sslServerCert = certificatePath;
          sslServerKey = keyPath;
          enableLmtp = true;
          mailPlugins.globally.enable =
            lib.optionals cfg.fullTextSearch.enable [ "fts" "fts_flatcurve" ];
          protocols = lib.optional cfg.enableManageSieve "sieve";

          pluginSettings = {
            sieve =
              "file:${cfg.sieveDirectory}/%{user}/scripts;active=${cfg.sieveDirectory}/%{user}/active.sieve";
            sieve_default = "file:${cfg.sieveDirectory}/%{user}/default.sieve";
            sieve_default_name = "default";
          } // (lib.optionalAttrs cfg.fullTextSearch.enable ftsPluginSettings);

          sieve = {
            extensions = [ "fileinto" ];
            scripts.after = builtins.toFile "spam.sieve" ''
              require "fileinto";

              if header :is "X-Spam" "Yes" {
                  fileinto "${junkMailboxName}";
                  stop;
              }
            '';
            pipeBins = map lib.getExe [
              (pkgs.writeShellScriptBin "rspamd-learn-ham.sh"
                "exec ${pkgs.rspamd}/bin/rspamc -h /run/rspamd/worker-controller.sock learn_ham")
              (pkgs.writeShellScriptBin "rspamd-learn-spam.sh"
                "exec ${pkgs.rspamd}/bin/rspamc -h /run/rspamd/worker-controller.sock learn_spam")
            ];
          };
          imapsieve.mailbox = [
            {
              name = junkMailboxName;
              causes = [ "COPY" "APPEND" ];
              before = ./dovecot/imap_sieve/report-spam.sieve;
            }
            {
              name = "*";
              from = junkMailboxName;
              causes = [ "COPY" ];
              before = ./dovecot/imap_sieve/report-ham.sieve;
            }
          ];
          mailboxes = cfg.mailboxes;
          extraConfig = ''
            #Extra Config
            ${lib.optionalString debug ''
              mail_debug = yes
              auth_debug = yes
              verbose_ssl = yes
            ''}

            ${lib.optionalString (cfg.enableImap || cfg.enableImapSsl) ''
              service imap-login {
                inet_listener imap {
                  ${
                    if cfg.enableImap then ''
                      port = 143
                    '' else ''
                      # see https://dovecot.org/pipermail/dovecot/2010-March/047479.html
                      port = 0
                    ''
                  }
                }
                inet_listener imaps {
                  ${
                    if cfg.enableImapSsl then ''
                      port = 993
                      ssl = yes
                    '' else ''
                      # see https://dovecot.org/pipermail/dovecot/2010-March/047479.html
                      port = 0
                    ''
                  }
                }
              }
            ''}
            ${lib.optionalString (cfg.enablePop3 || cfg.enablePop3Ssl) ''
              service pop3-login {
                inet_listener pop3 {
                  ${
                    if cfg.enablePop3 then ''
                      port = 110
                    '' else ''
                      # see https://dovecot.org/pipermail/dovecot/2010-March/047479.html
                      port = 0
                    ''
                  }
                }
                inet_listener pop3s {
                  ${
                    if cfg.enablePop3Ssl then ''
                      port = 995
                      ssl = yes
                    '' else ''
                      # see https://dovecot.org/pipermail/dovecot/2010-March/047479.html
                      port = 0
                    ''
                  }
                }
              }
            ''}

            protocol imap {
              mail_max_userip_connections = ${
                toString cfg.maxConnectionsPerUser
              }
              mail_plugins = $mail_plugins imap_sieve
            }
            service imap {
              vsz_limit = ${builtins.toString cfg.imapMemoryLimit} MB
            }
            protocol pop3 {
              mail_max_userip_connections = ${
                toString cfg.maxConnectionsPerUser
              }
            }
            mail_access_groups = ${vmailGroupName}
            ssl = required
            ssl_min_protocol = TLSv1.2
            ssl_prefer_server_ciphers = no

            service lmtp {
              unix_listener dovecot-lmtp {
                group = ${postfixCfg.group}
                mode = 0600
                user = ${postfixCfg.user}
              }
              vsz_limit = ${builtins.toString cfg.lmtpMemoryLimit} MB
            }
            service quota-status {
              inet_listener {
                port = 0
              }
              unix_listener quota-status {
                user = postfix
              }
              vsz_limit = ${builtins.toString cfg.quotaStatusMemoryLimit} MB
            }

            recipient_delimiter = ${cfg.recipientDelimiter}
            lmtp_save_to_detail_mailbox = ${cfg.lmtpSaveToDetailMailbox}
            protocol lmtp {
              mail_plugins = $mail_plugins sieve
            }
            passdb {
              driver = passwd-file
              args = ${passwdFile}
            }
            userdb {
              driver = passwd-file
              args = ${userdbFile}
              default_fields = uid=${builtins.toString cfg.vmailUID} gid=${
                builtins.toString cfg.vmailUID
              } home=${cfg.mailDirectory}
            }
            ${lib.optionalString cfg.ldap.enable ''
              passdb {
                driver = ldap
                args = ${ldapConfFile}
              }
              userdb {
                driver = ldap
                args = ${ldapConfFile}
                default_fields = home=/var/vmail/ldap/%{user} uid=${
                  toString cfg.vmailUID
                } gid=${toString cfg.vmailUID}
              }
            ''}
            service auth {
              unix_listener auth {
                mode = 0660
                user = ${postfixCfg.user}
                group = ${postfixCfg.group}
              }
            }
            auth_mechanisms = plain login
            namespace inbox {
              separator = ${cfg.hierarchySeparator}
              inbox = yes
            }
            service indexer-worker {
            ${lib.optionalString (cfg.fullTextSearch.memoryLimit != null) ''
              vsz_limit = ${
                toString (cfg.fullTextSearch.memoryLimit * 1024 * 1024)
              }
            ''}
            }
            lda_mailbox_autosubscribe = yes
            lda_mailbox_autocreate = yes
          '';
        }
        (lib.mkIf haveDovecotModulesOption { modules = dovecotModules; })
      ];
      systemd.services.dovecot2 = {
        preStart = ''
          ${genPasswdScript}
        '' + (lib.optionalString cfg.ldap.enable setPwdInLdapConfFile);
      };
      systemd.services.postfix.restartTriggers = [ genPasswdScript ]
        ++ (lib.optional cfg.ldap.enable [ setPwdInLdapConfFile ]);
    };
}
