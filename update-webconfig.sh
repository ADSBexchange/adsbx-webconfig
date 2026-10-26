#!/bin/bash

set -e
trap 'echo "[ERROR] Error in line $LINENO when executing: $BASH_COMMAND"' ERR

# in case /var/log is full ... delete some logs
echo test > /var/log/.test 2>/dev/null || rm -f /var/log/*.log

function aptInstall() {
    if ! apt install -y --no-install-recommends --no-install-suggests "$@"; then
        apt update
        apt install -y --no-install-recommends --no-install-suggests "$@"
    fi
}

aptInstall git

cd /tmp
updir=/tmp/update-webconfig

rm -rf $updir
git clone --depth 1 https://github.com/ADSBexchange/adsbx-webconfig.git $updir

cd $updir
bash install.sh dont_reset_config

# pick up Debian security updates for the installed PHP release
php_packages=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'php*' 2>/dev/null | awk '$1 == "ii" {print $2}')
if [[ -n "$php_packages" ]]; then
    if apt-get install -y --only-upgrade --no-install-recommends $php_packages \
        || { apt update && apt-get install -y --only-upgrade --no-install-recommends $php_packages; }; then
        systemctl restart lighttpd
    else
        echo "WARNING: PHP package upgrade failed, continuing"
    fi
fi

cd /tmp
rm -rf $updir

echo "8.2.$(date '+%y%m%d')" > /boot/adsbx-version-webconfig

echo '--------------------------------------------'
echo '        update-webconfig complete.          '
echo '--------------------------------------------'
