#!/bin/bash

log=/adsbexchange/adsbx-update.log
rm -f $log
exec &> >(tee -a "$log")

export DEBIAN_FRONTEND=noninteractive

# progress markers read by the web UI: "== step <id> <start|ok|failed> (<time>)[: <message>]"
step() {
    echo "== step $1 $2 ($(date +%H:%M:%S))${3:+: $3}"
}

# This is required for low memory devices, else apt update locks
sudo dphys-swapfile swapon

step apt-update start
if apt update; then
    step apt-update ok
else
    step apt-update failed
fi
#apt upgrade -y

# software status before and after, shown on the update page as "last update"
status_helper=/adsbexchange/webconfig/helpers/update-status.sh
result_file=/adsbexchange/update-result.json
started=$(date -Is)
before=$("$status_helper" 2>/dev/null)
write_result() {
    local after markers
    after=$("$status_helper" 2>/dev/null)
    markers=$(grep '^== step ' "$log" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\"%s\"", (NR > 1 ? "," : ""), $0}')
    printf '{"started":"%s","finished":"%s","result":"%s","before":%s,"after":%s,"markers":[%s]}\n' \
        "$started" "$(date -Is)" "$1" "${before:-null}" "${after:-null}" "$markers" > "$result_file"
}

failed=0
# run_script <step-id> <url>: downloads the script and runs it; a failed download or run marks the update failed
run_script() {
    local script
    step "$1" start
    if ! script="$(wget -nv -O - "$2")" || [[ -z "$script" ]]; then
        echo "UPDATE ERROR: download failed: $2"
        step "$1" failed "download failed"
        failed=1
    elif ! bash -c "$script"; then
        echo "UPDATE ERROR: script failed: $2"
        step "$1" failed "script failed"
        failed=1
    else
        step "$1" ok
    fi
}
run_script feed-software https://raw.githubusercontent.com/ADSBexchange/adsbx-update/main/update-adsbx.sh
run_script web-ui https://raw.githubusercontent.com/ADSBexchange/adsbx-webconfig/master/update-webconfig.sh

if [[ $failed != 0 ]]; then
    write_result failed
    echo "Update did not complete, not rebooting. See the errors above."
    exit 1
fi

write_result ok
step reboot start
echo "rebooting..."
sleep 5
reboot now
