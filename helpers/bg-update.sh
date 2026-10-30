#!/bin/bash

log=/adsbexchange/adsbx-update.log
rm -f $log
exec &> >(tee -a "$log")

export DEBIAN_FRONTEND=noninteractive

# This is required for low memory devices, else apt update locks
sudo dphys-swapfile swapon

apt update
#apt upgrade -y

# software status before and after, shown on the update page as "last update"
status_helper=/adsbexchange/webconfig/helpers/update-status.sh
result_file=/adsbexchange/update-result.json
started=$(date -Is)
before=$("$status_helper" 2>/dev/null)
write_result() {
    local after
    after=$("$status_helper" 2>/dev/null)
    printf '{"started":"%s","finished":"%s","result":"%s","before":%s,"after":%s}\n' \
        "$started" "$(date -Is)" "$1" "${before:-null}" "${after:-null}" > "$result_file"
}

failed=0
for url in \
    https://raw.githubusercontent.com/ADSBexchange/adsbx-update/main/update-adsbx.sh \
    https://raw.githubusercontent.com/ADSBexchange/adsbx-webconfig/master/update-webconfig.sh
do
    if ! script="$(wget -nv -O - "$url")" || [[ -z "$script" ]]; then
        echo "UPDATE ERROR: download failed: $url"
        failed=1
    elif ! bash -c "$script"; then
        echo "UPDATE ERROR: script failed: $url"
        failed=1
    fi
done

if [[ $failed != 0 ]]; then
    write_result failed
    echo "Update did not complete, not rebooting. See the errors above."
    exit 1
fi

write_result ok
echo "rebooting..."
sleep 5
reboot now
