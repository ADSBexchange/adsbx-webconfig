#!/bin/bash
# auto-updates.sh status|enable|disable
# Automatic installation of Debian security updates through unattended-upgrades, driven by the
# apt-daily timers. The policy (security origin only, no reboot, excluded packages) is written by
# install.sh to /etc/apt/apt.conf.d/52-adsbx-unattended-upgrades.

periodic=/etc/apt/apt.conf.d/20auto-upgrades
logfile=/var/log/unattended-upgrades/unattended-upgrades.log
saved=/adsbexchange/auto-updates-last
timers="apt-daily.timer apt-daily-upgrade.timer"

esc() {
    local s=${1//\\/\\\\}
    s=${s//\"/\\\"}
    printf '%s' "$s"
}

case $1 in
    enable)
        printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > "$periodic"
        systemctl unmask $timers >/dev/null 2>&1 || true
        systemctl enable --now $timers
        ;;
    disable)
        printf 'APT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";\n' > "$periodic"
        systemctl disable --now $timers >/dev/null 2>&1 || true
        ;;
    status)
        installed=false
        dpkg-query -W -f='${db:Status-Abbrev}' unattended-upgrades 2>/dev/null | grep -q '^ii' && installed=true
        enabled=false
        if grep -qs 'APT::Periodic::Unattended-Upgrade "1"' "$periodic" && systemctl is-enabled apt-daily-upgrade.timer >/dev/null 2>&1; then
            enabled=true
        fi
        last_run=; last_outcome=
        if [[ -r $logfile ]]; then
            block=$(awk '/Starting unattended upgrades script/ {buf = ""} {buf = buf $0 "\n"} END {printf "%s", buf}' "$logfile")
            last_run=$(printf '%s' "$block" | grep 'Starting unattended upgrades script' | head -n 1 | cut -c1-16)
            if printf '%s' "$block" | grep -q 'No packages found that can be upgraded unattended'; then
                last_outcome="nothing to install"
            elif printf '%s' "$block" | grep -q 'All upgrades installed'; then
                last_outcome="installed: $(printf '%s' "$block" | sed -n 's/.*Packages that will be upgraded: //p' | tail -n 1)"
            elif printf '%s' "$block" | grep -q 'Packages that will be upgraded'; then
                last_outcome="did not finish: $(printf '%s' "$block" | sed -n 's/.*Packages that will be upgraded: //p' | tail -n 1)"
            fi
        fi
        # /var/log does not survive a reboot on the feeder image: keep the last run's summary elsewhere
        if [[ -n $last_run ]]; then
            printf '%s\n%s\n' "$last_run" "$last_outcome" > "$saved"
        elif [[ -r $saved ]]; then
            { read -r last_run; read -r last_outcome; } < "$saved"
        fi
        next_run=
        if [[ $enabled == true ]]; then
            next_run=$(systemctl show apt-daily-upgrade.timer -p NextElapseUSecRealtime --value 2>/dev/null | cut -c1-20)
        fi
        printf '{"installed":%s,"enabled":%s,"last_run":"%s","last_outcome":"%s","next_run":"%s"}\n' \
            "$installed" "$enabled" "$(esc "$last_run")" "$(esc "$last_outcome")" "$(esc "$next_run")"
        ;;
    *)
        echo "usage: $0 status|enable|disable" >&2
        exit 2
        ;;
esac
