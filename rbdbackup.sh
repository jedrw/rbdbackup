#!/bin/bash
set -e

CONFIG=$1
DEFAULT_POOL=$(yq -r .defaultPool "${CONFIG}")
DEFAULT_DESTINATION=$(yq -r .defaultDestination "${CONFIG}")
TMP_MOUNT_DIR="/mnt/tmp-vdisk"

underline_message () {
    printf -- '-%.s' $(eval "echo {1.."$(echo -n "${1}" | wc -m)"}")
    echo
}

get_backup_volumes () {
    yq -r '.backups[].volume' "${CONFIG}"
}

get_pool_for_volume () {
    local POOL=$(yq -r ".backups[] | select(.volume == \"$1\") | .pool" "${CONFIG}")
    echo ${POOL/null/"${DEFAULT_POOL}"}
}

get_destination_for_volume () {
    local DESTINATION=$(yq -r ".backups[] | select(.volume == \"$1\") | .destination" "${CONFIG}")
    echo ${DESTINATION/null/"${DEFAULT_DESTINATION}"}
}

cleanup () {
    # Keep truckin
    set +e
    umount "${1}"
    rbd device unmap "${2}"
    rmdir "${1}"
    # Stop truckin
    set -e
}

for VOLUME in $(get_backup_volumes); do
    MESSAGE="Backing up ${VOLUME}"
    echo "${MESSAGE}"
    underline_message "${MESSAGE}"

    POOL=$(get_pool_for_volume "${VOLUME}")
    DESTINATION=$(get_destination_for_volume "${VOLUME}")
    
    MOUNT_PATH="${TMP_MOUNT_DIR}/${VOLUME}"
    mkdir -p "${MOUNT_PATH}"

    # At this point whatever happens make sure to cleanup
    trap "cleanup '${MOUNT_PATH}' '${RBD_DEVICE}'" ERR SIGINT
    
    RBD_DEVICE=$(rbd device map --pool "${POOL}" "${VOLUME}")
    mount "${RBD_DEVICE}" "${MOUNT_PATH}"
    rsync -av --del --exclude "lost+found" "${MOUNT_PATH}" "${DESTINATION}"
    
    # All is good in the world, reset the trap for ERR and SIGINT
    trap - ERR SIGINT
    cleanup "${MOUNT_PATH}" "${RBD_DEVICE}"
    echo
done