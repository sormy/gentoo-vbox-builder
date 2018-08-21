#!/bin/bash

# global SSH_OPTS

wait_until_ssh_will_be_up() {
    # global SSH_OPTS

    local user="$1"
    local host="$2"
    local port="${3:-22}"
    local max_attempts="${4:-5}"
    local interval="${5:-15}"

    local attempt=0

    while : ; do
        attempt=$(expr $attempt + 1)

        einfo "Waiting until SSH will be up ($attempt/$max_attempts)..."

        ssh $SSH_OPTS "$user@$host" -p "$port" "exit" && break || true
        [ $attempt = $max_attempts ] && return 1 || true

        sleep $interval
    done
}
