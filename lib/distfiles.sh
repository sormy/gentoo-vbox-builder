#!/bin/bash

# global CURL_OPTS
# global GENTOO_GPG_SERVER
# global GENTOO_GPG_KEYS

download_distfile_safe() {
    # global CURL_OPTS
    # global GENTOO_GPG_SERVER
    # global GENTOO_GPG_KEYS

    local url="$1"
    local file="$2"

    edebug "Download URL: $url"
    edebug "Download File: $file"
    local expected_hash
    local actual_hash
    local hash
    local hash_verified=0

    if [[ -f "$file" && -f "$file.DIGESTS" ]]; then 
        edebug "Found $file and $file.DIGESTS, skiping download"
    else
        edebug "Did not find both $file and $file.DIGESTS, downloading now."
        eexec curl $CURL_OPTS \
            -o "$file" "$url" \
        -o "$file.DIGESTS" "$url.DIGESTS"
    fi

    for hash in sha512 whirlpool; do
        expected_hash="$(grep -i "$hash" -A 1 < "$file.DIGESTS" \
            | grep -v '^[#-]' | grep -v '\.CONTENTS\.' | cut -d" " -f1)"

        if [ -n "$expected_hash" ]; then
            einfo "Verifying $hash hash..."

            actual_hash="$(openssl dgst -r -$hash "$file" | cut -d" " -f1)"

            if [ "$expected_hash" != "$actual_hash" ]; then
                eerror "$hash hash verification failed."
                eerror "Expected $hash: $expected_hash"
                eerror "Actual $hash: $actual_hash"
                edebug "Cleaning up faulty distfiles ..."
                download_distfile_cleanup
                exit 1
            else
                hash_verified=1
            fi
        fi
    done

    if [ "$hash_verified" = 0 ]; then
        eerror "Unable to find any applicable hash to verify"
        exit 1
    fi

    einfo "Verifying GPG signature..."

    eexec gpg --keyserver $GENTOO_GPG_SERVER --recv-keys $GENTOO_GPG_KEYS

    eexec gpg --verify "$file.DIGESTS" \
        || edie "GPG signature verification failed."
}

download_distfile_cleanup() {
    if [ -n "$GENTOO_LIVECD_TMP" ] && [ -e "$GENTOO_LIVECD_TMP" ]; then
        edebug "Removing $GENTOO_LIVECD_TMP"
        rm  "$GENTOO_LIVECD_TMP"
    fi

    if [ -n "$GUEST_INIT_FILE" ] && [ -e "$GUEST_INIT_FILE" ]; then
        edebug "Removing $GUEST_INIT_FILE"
        rm "$GUEST_INIT_FILE"
    fi
}

