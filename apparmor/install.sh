#!/bin/sh
# One-time root install of cpb's netns helper and its AppArmor profile.
# Usage: sudo apparmor/install.sh
set -eu
here=$(dirname "$0")
install -o root -g root -m 0755 "$here/../libexec/cpb-netns" /usr/local/libexec/cpb-netns
install -o root -g root -m 0644 "$here/cpb-netns" /etc/apparmor.d/cpb-netns
apparmor_parser -r /etc/apparmor.d/cpb-netns
