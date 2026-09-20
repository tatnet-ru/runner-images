#!/bin/bash
# TatNet: аналог pre.sh без AWS-агентов (cloudwatch, ssm, efs-utils,
# runs-on-bootstrap) и с cloud-init, который умеет то, чем пул TatNet Runners
# конфигурирует ВМ: write_files (env агента), runcmd (старт юнита),
# growpart/resizefs (диск ВМ больше образа), hostname.
set -exo pipefail

cloud-init status --wait

cat > /root/.gemrc <<EOF
gem: --no-document
EOF

# Официальные зеркала Ubuntu по https — тест Apt.Tests.ps1 это проверяет.
arch=$(dpkg --print-architecture)
apt_primary_mirror="https://archive.ubuntu.com/ubuntu/"
apt_security_mirror="https://security.ubuntu.com/ubuntu/"
if [ "$arch" = "arm64" ]; then
  apt_primary_mirror="https://ports.ubuntu.com/ubuntu-ports/"
  apt_security_mirror="$apt_primary_mirror"
fi
rewrite_apt_source() {
  local f="$1"
  if [ -f "$f" ]; then
    sed -i -E \
      -e "s#https?://[^/]*\.ec2\.(archive|ports)\.ubuntu\.com/(ubuntu|ubuntu-ports)/?#${apt_primary_mirror}#g" \
      -e "s#https?://security\.ubuntu\.com/ubuntu/?#${apt_security_mirror}#g" \
      -e "s#https?://ports\.ubuntu\.com/ubuntu-ports/?#${apt_primary_mirror}#g" \
      -e "s#http://archive\.ubuntu\.com/ubuntu/?#${apt_primary_mirror}#g" \
      "$f"
  fi
}
for src in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do
  rewrite_apt_source "$src"
done

# Снапы cloud image не нужны раннеру; snapd целиком снимает runner-user.sh.
for s in amazon-ssm-agent lxd core20 core18; do
  snap remove "$s" || true
done
rm -rf /var/lib/snapd/seed/snaps
snap set system experimental.hotplug=false || true

# Как у runs-on: cc_apt_configure не должен звать lsb_release/dpkg на каждом
# старте — codename и arch вшиваются.
codename=$(lsb_release --codename -s)
sed -i 's|release = util.lsb_release()\["codename"\].*|release = "'$codename'"|w /dev/stdout' /usr/lib/python3/dist-packages/cloudinit/config/cc_apt_configure.py | grep $codename
sed -i 's|util.get_dpkg_architecture()|"'$arch'"|w /dev/stdout' /usr/lib/python3/dist-packages/cloudinit/config/cc_apt_configure.py | grep $arch
sed -i 's|util.get_dpkg_architecture()|"'$arch'"|w /dev/stdout' /usr/lib/python3/dist-packages/cloudinit/distros/debian.py | grep $arch

# Урезанный набор модулей cloud-init: быстрее старт, но НЕ короче, чем
# нужно пулу. runs-on оставляет только users_groups/ssh/apt/scripts_user —
# с таким списком write_files и runcmd из seed молча не исполняются, а
# корень не растёт под диск ВМ.
cat > /etc/cloud/cloud.cfg.d/01_tatnet.cfg <<EOF
ssh_quiet_keygen: true
allow_public_ssh_keys: true
disable_root: true
ssh_deletekeys: true
ssh_genkeytypes: [ed25519]

apt:
  preserve_sources_list: false
  primary:
    - arches: [default]
      uri: "${apt_primary_mirror}"
  security:
    - arches: [default]
      uri: "${apt_security_mirror}"

cloud_init_modules:
  - seed_random
  - write_files
  - growpart
  - resizefs
  - set_hostname
  - update_hostname
  - update_etc_hosts
  - users_groups
  - ssh

cloud_config_modules:
  - apt_configure
  - runcmd

cloud_final_modules:
  - scripts_user
  - final_message
EOF
