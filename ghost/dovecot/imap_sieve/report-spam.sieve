# /qompassai/ghost/ghost/dovecot/imap_sieve/report-spam.sieve
# Qompass AI Ghost IMAP Spam Reporting Sieve
# # Copyright (C) 2025 Qompass AI, All rights reserved
#######################################################
require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];
if environment :matches "imap.user" "*" {
  set "username" "${1}";
}
pipe :copy "rspamd-learn-spam.sh" [ "${username}" ];
