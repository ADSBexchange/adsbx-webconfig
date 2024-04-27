#!/bin/bash

cp /tmp/webconfig/adsbx-uiconfig.nmconnection /etc/NetworkManager/system-connections/adsbx-uiconfig.nmconnection
chmod 600 /etc/NetworkManager/system-connections/*
rm -f /tmp/webconfig/adsbx-uiconfig.nmconnection
raspi-config nonint do_wifi_country $(cat /tmp/webconfig/wificountry)
nmcli 
sleep 5
reboot now

  
