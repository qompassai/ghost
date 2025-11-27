# /qompassai/ghost/ghost/dovecot/imap_sieve/report-ham.sieve
# Qompass AI Ghost IMAP Ham Reporting Sieve
# # Copyright (C) 2025 Qompass AI, All rights reserved
#######################################################
require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];

if environment :matches "imap.mailbox" "*" {
  set "mailbox" "${1}";
}

if string "${mailbox}" "Trash" {
  stop;
}

if environment :matches "imap.user" "*" {
  set "username" "${1}";
}

pipe :copy "rspamd-learn-ham.sh" [ "${username}" ];
