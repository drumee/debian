#!/bin/bash
cd /var/tmp/drumee/packages || exit 1
curl -O https://app.drumee.com/debian/patches/packages/drumee-patch_1.0.1_all.deb
curl -O https://app.drumee.com/debian/patches/packages/drumee-server-pod_2.6.20_all.deb
curl -O https://app.drumee.com/debian/patches/packages/drumee-ui-pod_2.8.22_all.deb

dpkg -i drumee-patch_1.0.1_all.deb
dpkg -i drumee-server-pod_2.6.20_all.deb
dpkg -i drumee-ui-pod_2.8.22_all.deb
drumee start main
drumee start main/service
