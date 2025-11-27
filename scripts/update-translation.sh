#!/usr/bin/env sh
# /qompassai/ghost/scripts/update-translation.sh
# Qompass AI Ghost Translation Update Script
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
PHP_FILES=""
find . -iname '*.php' -print >/tmp/phpfiles.$$
while IFS= read -r file; do
    PHP_FILES="$PHP_FILES \"$file\""
done </tmp/phpfiles.$$
rm /tmp/phpfiles.$$
eval "xgettext --from-code=UTF-8 -o locale/mail-hosting.pot $PHP_FILES"
find locale -iname '*.po' -print | while IFS= read -r translation; do
    msgmerge -U "$translation" locale/mail-hosting.pot
    mo_file=$(printf '%s\n' "$translation" | sed 's/\.po$/.mo/')
    msgfmt -o "$mo_file" "$translation"
done
