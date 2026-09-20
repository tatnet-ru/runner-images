#!/bin/bash
# TatNet: то, чем образ отличается от runs-on в рантайме. Идёт ПОСЛЕ
# runner-user.sh (он кладёт actions/runner в /home/runner и гасит юниты).
#
# 1. qemu-guest-agent — платформа TatNet опирается на него (проба
#    готовности, reset_vm_password, quiesce снапшотов).
# 2. Загрузчик агента TatNet Runners и его юнит: env (URL control, токен,
#    бинарь и sha256) кладёт cloud-init через write_files, юнит стартует по
#    runcmd; WantedBy=cloud-init.target, а не multi-user — из multi-user
#    юнит с After=cloud-final образует цикл и не стартует (замер 20.09.2026
#    на слим-образе).
# 3. Docker включён как юнит: на GitHub-hosted dockerd запущен, а socket-
#    активация даёт паузу на первом вызове и «inactive» тому, кто проверяет.
# 4. runner в группе docker — как на GitHub-hosted.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get install -y qemu-guest-agent
systemctl enable qemu-guest-agent

cat > /usr/local/bin/tatnet-runners-bootstrap <<'EOF'
#!/bin/sh
set -eu
: "${RUNNERS_AGENT_URL:?}" "${RUNNERS_AGENT_SHA256:?}"
tmp=$(mktemp)
curl -fsSL --retry 5 --retry-delay 2 -o "$tmp" "$RUNNERS_AGENT_URL"
echo "$RUNNERS_AGENT_SHA256  $tmp" | sha256sum -c - >/dev/null
install -m 0755 "$tmp" /usr/local/bin/runners-agent
rm -f "$tmp"
EOF
chmod 0755 /usr/local/bin/tatnet-runners-bootstrap

mkdir -p /etc/tatnet
cat > /etc/systemd/system/tatnet-runners-agent.service <<'EOF'
[Unit]
Description=TatNet Runners agent
After=network-online.target cloud-final.service docker.service
Wants=network-online.target docker.service
ConditionPathExists=/etc/tatnet/runners-agent.env

[Service]
EnvironmentFile=/etc/tatnet/runners-agent.env
Environment=RUNNERS_RUNNER_DIR=/home/runner
ExecStartPre=/usr/local/bin/tatnet-runners-bootstrap
ExecStart=/usr/local/bin/runners-agent
Restart=on-failure
RestartSec=5

[Install]
WantedBy=cloud-init.target
EOF
systemctl enable tatnet-runners-agent

systemctl enable containerd.service docker.service
usermod -aG docker runner

# chrony — часы гостя (kvm-clock отдаёт сырой TSC хоста, гость обязан
# дисциплинировать часы сам); runner-user.sh его уже поставил.
systemctl enable chrony || true

# Версия раннера — ТОЛЬКО от пользователя runner: Runner.Listener на любом
# вызове заводит /home/runner/_diag, и созданный root'ом каталог потом
# роняет раннер у пользователя runner («Access to the path … _diag … is
# denied», exit 134 — первая джоба на этом образе, 20.09.2026).
runner_version=$(sudo -u runner /home/runner/bin/Runner.Listener --version 2>/dev/null || echo "?")
rm -rf /home/runner/_diag
chown -R runner:runner /home/runner
{
  echo "tatnet-runtime $(date -u +%F)"
  echo "actions-runner ${runner_version}"
} >> /etc/tatnet-ci-runner.versions || true
