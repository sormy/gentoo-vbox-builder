#!/bin/bash

# global WGET_OPTS
# global GENTOO_GPG_KEYS

download_distfile_safe() {
    # global WGET_OPTS
    # global GENTOO_GPG_KEYS

    local url="$1"
    local file="$2"

    local expected_hash
    local actual_hash
    local hash

    eexec wget $WGET_OPTS -O "$file" "$url"
    eexec wget $WGET_OPTS -O "$file.DIGESTS.asc" "$url.DIGESTS.asc"

    for hash in sha512 whirlpool; do
        einfo "Verifying $hash hash..."

        expected_hash="$(cat "$file.DIGESTS.asc" | grep -i "$hash" -A 1 | grep -v '^[#-]' | grep -v '\.CONTENTS$' | cut -d" " -f1)"
        actual_hash="$(openssl dgst -r -$hash "$file" | cut -d" " -f1)"

        if [ "$expected_hash" != "$actual_hash" ]; then
            eerror "$hash hash verification failed."
            eerror "Expected $hash: $expected_hash"
            eerror "Actual $hash: $actual_hash"
            exit 1
        fi
    done

    if [ -z "$(command -v gpg)" ]; then
        ewarn "Unable to verify GPG signature due to missing GnuPG."
    else
        einfo "Verifying GPG signature..."

        eexec gpg --keyserver hkps.pool.sks-keyservers.net \
            --recv-keys $GENTOO_GPG_KEYS

        eexec gpg --verify "$file.DIGESTS.asc" \
            || edie "GPG signature verification failed."
    fi
}

download_portage_safe() {
    # global WGET_OPTS
    # global GENTOO_GPG_KEYS

    local url="$1"
    local file="$2"

    local expected_hash
    local actual_hash

    eexec wget $WGET_OPTS -O "$file" "$url"
    eexec wget $WGET_OPTS -O "$file.md5sum" "$url.md5sum"
    eexec wget $WGET_OPTS -O "$file.gpgsig" "$url.gpgsig"

    expected_hash="$(cat "$file.md5sum" | grep -v '^[#-]' | cut -d" " -f1)"
    actual_hash="$(openssl dgst -r -md5 "$file" | cut -d" " -f1)"

    if [ "$expected_hash" != "$actual_hash" ]; then
        eerror "md5 hash verification failed."
        eerror "Expected md5: $expected_hash"
        eerror "Actual md5: $actual_hash"
        exit 1
    fi

    if [ -z "$(command -v gpg)" ]; then
        ewarn "Unable to verify GPG signature due to missing GnuPG."
    else
        einfo "Verifying GPG signature..."

        eexec gpg --keyserver hkps.pool.sks-keyservers.net \
            --recv-keys $GENTOO_GPG_KEYS

        eexec gpg --verify "$file.gpgsig" "$file" \
            || edie "GPG signature verification failed."
    fi
}
