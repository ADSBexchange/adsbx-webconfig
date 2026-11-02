#!/bin/bash

if [ $(id -u) -ne 0 ]; then
  echo -e "This script must be run as root. \n"
  exit 1
fi

trap 'echo "[ERROR] Error in line $LINENO when executing: $BASH_COMMAND"' ERR

# Devices fetch this file from master on every update. The web UI they install comes from a
# release branch chosen here; see CONTRIBUTING.md. WEBCONFIG_DISPATCH=no installs this checkout
# instead (set by the hand-off below, and used for tests and image builds of a branch).
if [[ ${WEBCONFIG_DISPATCH:-yes} != no ]]; then
    codename=$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-unknown}")
    if systemctl is-enabled NetworkManager.service >/dev/null 2>&1; then nm=yes; else nm=no; fi
    case "$codename:$nm" in
        buster:no|bullseye:no) line=release/8.x ;;
        bookworm:yes)          line=release/9.x ;;
        *)
            echo "No web UI release matches this system (os=$codename, networkmanager=$nm); keeping the installed version."
            exit 1 ;;
    esac
    linedir=/tmp/update-webconfig-${line##*/}
    rm -rf "$linedir"
    if ! git clone --quiet --depth 1 -b "$line" https://github.com/ADSBexchange/adsbx-webconfig.git "$linedir"; then
        echo "Could not fetch $line; keeping the installed version."
        exit 1
    fi
    cd "$linedir" && WEBCONFIG_DISPATCH=no bash ./install.sh "$@" && rc=0 || rc=$?
    cd / && rm -rf "$linedir"
    exit "$rc"
fi

function aptInstall() {
    if ! apt install -y --no-install-recommends --no-install-suggests "$@"; then
        apt update
        apt install -y --no-install-recommends --no-install-suggests "$@"
    fi
}

if ! [[ -f /boot/adsbx-version ]]; then
    echo 8.0123456789 > /boot/adsbx-version
fi

aptInstall whois php-common php-cgi dnsmasq
command -v rsyslogd &>/dev/null && apt remove -y rsyslog || true

# pick up the latest available builds of the installed PHP and lighttpd packages
packages=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'php*' lighttpd 2>/dev/null | awk '$1 == "ii" {print $2}')
if [[ -n "$packages" ]]; then
    apt-get install -y --only-upgrade --no-install-recommends $packages \
        || { apt update && apt-get install -y --only-upgrade --no-install-recommends $packages; } \
        || echo "WARNING: package upgrade failed, continuing"
fi

lighttpd-enable-mod fastcgi-php 2>&1 | grep -F -v -e 'force-reload'

for dir in /etc/php/*; do
    echo -e "; Put session info here, to prevent SD card writes\nsession.save_path = \"/tmp\"" > "$dir/cgi/conf.d/30-session_path.ini" || true
    echo -e "session.cookie_httponly = 1\nsession.cookie_samesite = Lax\nsession.use_strict_mode = 1\nexpose_php = Off" > "$dir/cgi/conf.d/40-webconfig.ini" || true
done

systemctl restart lighttpd
systemctl disable dnsmasq &>/dev/null
systemctl stop dnsmasq || true

# lighttpd runs php-cgi itself; php-fpm is not used
for unit in $(systemctl list-unit-files 'php*-fpm.service' --no-legend | awk '{print $1}'); do
    systemctl disable --now "$unit" || true
done

ipath=/adsbexchange/webconfig

mkdir -p $ipath
cp adsb-config.txt.webtemplate webconfig.sh leds.sh sanitize-uuid.sh $ipath
cp ./webconfig.service /etc/systemd/system/
cp ./leds.service /etc/systemd/system/
rm -f /var/www/html/index.htm*
cp -r ./html/* /var/www/html
cp ./adsbx-config.nmconnection /etc/NetworkManager/system-connections/
chmod 600 /etc/NetworkManager/system-connections/adsbx-config.nmconnection
# cp ./dnsmasq.conf /etc/

rm -rf $ipath/helpers
cp -r -T ./helpers $ipath/helpers
chmod a+x $ipath/helpers/*.sh

# automatic security updates: installed and configured here, enabled only from the update page
first_auto_updates=no
[[ -f /etc/apt/apt.conf.d/52-adsbx-unattended-upgrades ]] || first_auto_updates=yes
aptInstall unattended-upgrades
cat > /etc/apt/apt.conf.d/52-adsbx-unattended-upgrades <<'EOF'
// Written by the ADS-B Exchange web UI installer: Debian security updates only, no automatic
// reboot, kernel/firmware/network packages left alone. Turned on or off from the update page.
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
};
#clear Unattended-Upgrade::Package-Blacklist;
Unattended-Upgrade::Package-Blacklist {
    "linux-image-";
    "raspberrypi-";
    "rpi-eeprom";
    "network-manager";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Remove-New-Unused-Dependencies "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "false";
EOF
if [[ $first_auto_updates == yes ]]; then
    bash $ipath/helpers/auto-updates.sh disable
fi

# record which checkout is installed, for the software status on the update page
{
    echo "branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "installed=$(date -Is)"
} > $ipath/version
cp ./010_www-data /etc/sudoers.d/
for file in helpers/*.sh; do
    echo "www-data ALL = NOPASSWD: /adsbexchange/webconfig/$file" >> /etc/sudoers.d/010_www-data
done

rm -rf /adsbexchange/update
mkdir -p /adsbexchange
git clone --depth 1 https://github.com/ADSBexchange/adsbx-update.git /adsbexchange/update

pushd /adsbexchange/update/
# always copy over this file
cp -v -T boot-configs/wpa_supplicant.conf /boot/wpa_supplicant.conf.bak
if [[ "$1" != "dont_reset_config" ]]; then
    cp -v -T boot-configs/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
    chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
    cp -v boot-configs/* /boot

    echo -e "\n UNLOCKING UNIT UNTIL FIRST CONFIG"
    touch /boot/unlock
fi
popd

# We do not use hostapd. Setup network is open.
systemctl disable hostapd &>/dev/null || true
systemctl enable webconfig
systemctl enable leds
systemctl restart webconfig
systemctl restart leds || true
