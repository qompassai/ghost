#!/usr/bin/env bash
# keystore.sh — generate Ghost's Android release signing keystore.
#
# Purpose:
#   Create the release keystore used to sign Ghost builds for Google
#   Play (and self-distributed APKs). F-Droid signs with its own key
#   and never needs this file.
#
# Usage:
#   scripts/publish/keystore.sh [--dry-run] [--help]
#
# Arguments:
#   --dry-run   Print every action instead of performing it. The ONLY
#               filesystem change a dry run makes is creating the
#               target directory, so the layout can be inspected.
#   --help      Show this header and exit.
#
# Environment:
#   GHOST_KEYSTORE_PASSWORD   Store + key password. When unset, the
#                             script prompts on /dev/tty (never echoes,
#                             never logs). Required non-interactively.
#   GHOST_KEYSTORE_DN         Distinguished name for the certificate.
#                             Default: "CN=Qompass AI, O=Qompass AI".
#   XDG_DATA_HOME             Base for the keystore location
#                             (default: ~/.local/share).
#
# Side effects (real run):
#   - Creates $XDG_DATA_HOME/keystores/ghost/ (mode 700).
#   - Creates ghost-release.jks inside it (mode 600) and a
#     ghost-keystore.properties file (paths + alias only, NO secrets).
#   - REFUSES to overwrite an existing keystore: a signing key is an
#     identity; losing or replacing it breaks every future update.
#
# Exit codes: 0 success, 1 error, 2 usage error.
# Required tools: keytool (JDK), timeout (coreutils).

set -euo pipefail

if ((BASH_VERSINFO[0] < 4)); then
    printf 'keystore.sh: bash >= 4 required (found %s)\n' "$BASH_VERSION" >&2
    exit 1
fi

readonly APP_NAME='ghost'
readonly KEY_ALIAS='ghost-release'
readonly KEYSTORE_FILENAME='ghost-release.jks'
readonly PROPERTIES_FILENAME='ghost-keystore.properties'
readonly KEY_ALG='RSA'
readonly KEY_SIZE='4096'
readonly SIG_ALG='SHA256withRSA'
readonly VALIDITY_DAYS='9125'
readonly KEYTOOL_TIMEOUT_S='120'
readonly PASSWORD_CHARS_MIN=6
readonly DEFAULT_DN='CN=Qompass AI, O=Qompass AI'

DRY_RUN=0

die() {
    printf 'keystore.sh: error: %s\n' "$*" >&2
    exit 1
}

usage() {
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# run <description> <command...>: execute, or print under --dry-run.
run() {
    local description="$1"
    shift
    if ((DRY_RUN)); then
        printf 'DRY-RUN: %s\n' "$description"
        printf 'DRY-RUN:   $'
        printf ' %q' "$@"
        printf '\n'
    else
        printf '+ %s\n' "$description"
        "$@"
    fi
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                ;;
            --help | -h)
                usage
                exit 0
                ;;
            *)
                printf 'keystore.sh: unknown argument: %s\n' "$1" >&2
                usage >&2
                exit 2
                ;;
        esac
        shift
    done
}

resolve_password() {
    if [[ -n "${GHOST_KEYSTORE_PASSWORD:-}" ]]; then
        return 0
    fi
    if [[ -t 0 && -r /dev/tty ]]; then
        local first='' second=''
        printf 'Enter keystore password: ' >/dev/tty
        IFS= read -r -s first </dev/tty
        printf '\nRe-enter keystore password: ' >/dev/tty
        IFS= read -r -s second </dev/tty
        printf '\n' >/dev/tty
        [[ "$first" == "$second" ]] || die 'passwords do not match'
        GHOST_KEYSTORE_PASSWORD="$first"
        export GHOST_KEYSTORE_PASSWORD
        return 0
    fi
    die 'GHOST_KEYSTORE_PASSWORD is unset and no terminal is available to prompt'
}

main() {
    parse_args "$@"

    command -v keytool >/dev/null 2>&1 || die 'keytool not found (install a JDK)'

    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local keystore_dir="$data_home/keystores/$APP_NAME"
    local keystore_path="$keystore_dir/$KEYSTORE_FILENAME"
    local properties_path="$keystore_dir/$PROPERTIES_FILENAME"
    local dn="${GHOST_KEYSTORE_DN:-$DEFAULT_DN}"

    # The directory is created even in dry-run mode, by design, so the
    # layout exists for inspection. Nothing else is written on dry-run.
    printf '+ create keystore directory: %s\n' "$keystore_dir"
    mkdir -p -- "$keystore_dir"
    chmod 700 "$keystore_dir"

    if [[ -e "$keystore_path" ]]; then
        die "keystore already exists at $keystore_path — refusing to overwrite a signing key"
    fi

    resolve_password
    if ((${#GHOST_KEYSTORE_PASSWORD} < PASSWORD_CHARS_MIN)); then
        die "password must be at least $PASSWORD_CHARS_MIN characters (keytool requirement)"
    fi
    export GHOST_KEYSTORE_PASSWORD

    # Passwords travel via keytool's :env form, never on the command
    # line where `ps` could read them.
    run 'generate release key pair' \
        timeout "$KEYTOOL_TIMEOUT_S" keytool -genkeypair \
        -keystore "$keystore_path" \
        -storetype PKCS12 \
        -storepass:env GHOST_KEYSTORE_PASSWORD \
        -keypass:env GHOST_KEYSTORE_PASSWORD \
        -alias "$KEY_ALIAS" \
        -keyalg "$KEY_ALG" \
        -keysize "$KEY_SIZE" \
        -sigalg "$SIG_ALG" \
        -validity "$VALIDITY_DAYS" \
        -dname "$dn"

    run 'restrict keystore permissions to owner' \
        chmod 600 "$keystore_path"

    if ((DRY_RUN)); then
        printf 'DRY-RUN: write %s with:\n' "$properties_path"
        printf 'DRY-RUN:   storeFile=%s\n' "$keystore_path"
        printf 'DRY-RUN:   keyAlias=%s\n' "$KEY_ALIAS"
    else
        printf '+ write %s\n' "$properties_path"
        printf 'storeFile=%s\nkeyAlias=%s\n' "$keystore_path" "$KEY_ALIAS" \
            >"$properties_path"
        chmod 600 "$properties_path"
    fi

    run 'show the new certificate fingerprint (verify this out of band)' \
        keytool -list -v \
        -keystore "$keystore_path" \
        -storepass:env GHOST_KEYSTORE_PASSWORD \
        -alias "$KEY_ALIAS"

    if ((DRY_RUN)); then
        printf 'DRY-RUN: complete — no keystore was created.\n'
    else
        printf 'Done. Back up %s somewhere safe; it cannot be regenerated.\n' \
            "$keystore_path"
    fi
}

main "$@"
