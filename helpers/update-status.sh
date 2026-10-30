#!/bin/bash
# update-status.sh [--check]
# Prints the installed feeder software components as JSON. With --check, also looks up the
# current tip of each component's source and reports whether an update is available.

check=no
[[ $1 == --check ]] && check=yes

esc() {
    local s=${1//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/ }
    printf '%s' "$s"
}

# remote <url> <ref>: full commit id of <ref> at <url>, empty when not checking or unreachable
remote() {
    [[ $check == yes ]] || return 0
    timeout 15 git ls-remote "$1" "$2" 2>/dev/null | awk '{print $1; exit}'
}

# status <installed-ref> <available-ref>
status() {
    local installed=$1 available=$2
    if [[ $check != yes ]]; then
        printf ''
    elif [[ -z $installed || -z $available ]]; then
        printf 'unknown'
    elif [[ $available == "$installed"* ]]; then
        printf 'up-to-date'
    else
        printf 'update-available'
    fi
}

# component <id> <name> <installed> <installed-ref> <available-ref> <source>
component() {
    printf '{"id":"%s","name":"%s","installed":"%s","installed_ref":"%s","available_ref":"%s","status":"%s","source":"%s"}' \
        "$(esc "$1")" "$(esc "$2")" "$(esc "$3")" "$(esc "$4")" "$(esc "$5")" "$(status "$4" "$5")" "$(esc "$6")"
}

components=()

readsb_line=$(readsb --version 2>&1 | head -n 1)
readsb_version=$(sed -n 's/^readsb version: \([^ ]*\).*/\1/p' <<< "$readsb_line")
readsb_ref=$(sed -n 's/.*git: \([0-9a-f]*\).*/\1/p' <<< "$readsb_line")
readsb_url=https://github.com/adsbexchange/readsb.git
components+=("$(component readsb "readsb (ADS-B decoder)" "${readsb_version:-unknown}${readsb_ref:+ $readsb_ref}" "$readsb_ref" "$(remote "$readsb_url" HEAD)" "$readsb_url")")

mlat_version=$(/usr/local/share/adsbexchange/venv/bin/python3 -c 'from mlat.client.version import CLIENT_VERSION; print(CLIENT_VERSION)' 2>/dev/null)
mlat_ref=$(cat /usr/local/share/adsbexchange/mlat_version /mlat_version 2>/dev/null | head -n 1)
mlat_url=https://github.com/adsbexchange/mlat-client.git
components+=("$(component mlat-client "mlat-client" "${mlat_version:-unknown}${mlat_ref:+ ${mlat_ref:0:7}}" "$mlat_ref" "$(remote "$mlat_url" HEAD)" "$mlat_url")")

tar1090_dir=/usr/local/share/tar1090/git
tar1090_ref=$(git -C "$tar1090_dir" rev-parse HEAD 2>/dev/null)
tar1090_date=$(git -C "$tar1090_dir" log -1 --date=short --format=%cd 2>/dev/null)
tar1090_url=$(git -C "$tar1090_dir" remote get-url origin 2>/dev/null)
tar1090_url=${tar1090_url:-https://github.com/wiedehopf/tar1090}
tar1090_branch=$(git -C "$tar1090_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
components+=("$(component tar1090 "tar1090 (map)" "${tar1090_ref:+${tar1090_ref:0:7} $tar1090_date}" "$tar1090_ref" "$(remote "$tar1090_url" "refs/heads/${tar1090_branch:-master}")" "$tar1090_url ${tar1090_branch:-master}")")

webconfig_branch=; webconfig_ref=; webconfig_installed=
if [[ -r /adsbexchange/webconfig/version ]]; then
    while IFS='=' read -r key value; do
        case $key in
            branch) webconfig_branch=$value ;;
            commit) webconfig_ref=$value ;;
            installed) webconfig_installed=$value ;;
        esac
    done < /adsbexchange/webconfig/version
fi
webconfig_url=https://github.com/ADSBexchange/adsbx-webconfig.git
components+=("$(component webconfig "Web UI" "${webconfig_ref:+${webconfig_branch:-?} ${webconfig_ref:0:7} ${webconfig_installed:0:10}}" "$webconfig_ref" "$(remote "$webconfig_url" "refs/heads/${webconfig_branch:-release/9.x}")" "$webconfig_url ${webconfig_branch:-release/9.x}")")

update_ref=$(git -C /adsbexchange/update rev-parse HEAD 2>/dev/null)
update_url=https://github.com/ADSBexchange/adsbx-update.git
components+=("$(component adsbx-update "Update scripts" "${update_ref:0:7}" "$update_ref" "$(remote "$update_url" HEAD)" "$update_url")")

for pkg in 'php[0-9]*-cgi' lighttpd; do
    name=$(dpkg-query -W -f='${Package}\n' "$pkg" 2>/dev/null | head -n 1)
    [[ -n $name ]] || continue
    installed=$(dpkg-query -W -f='${Version}' "$name" 2>/dev/null)
    candidate=$(apt-cache policy "$name" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
    [[ $check == yes ]] || candidate=
    components+=("$(component "$name" "$name (package)" "$installed" "$installed" "$candidate" "apt, candidate as of the last package list refresh")")
done

os=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")
image=$(cat /boot/adsbx-version 2>/dev/null)
decoder_stamp=$(cat /boot/adsbx-version-decoder 2>/dev/null)
webconfig_stamp=$(cat /boot/adsbx-version-webconfig 2>/dev/null)

printf '{"generated":"%s","checked":%s,"os":"%s","image":"%s","decoder_stamp":"%s","webconfig_stamp":"%s","components":[' \
    "$(date -Is)" "$([[ $check == yes ]] && echo true || echo false)" "$(esc "$os")" "$(esc "$image")" "$(esc "$decoder_stamp")" "$(esc "$webconfig_stamp")"
sep=
for c in "${components[@]}"; do
    printf '%s%s' "$sep" "$c"
    sep=,
done
printf ']}\n'
