require "minitest/autorun"
require "yaml"

class TatnetQemuTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  TEMPLATE = File.join(ROOT, "patches/ubuntu/templates/ubuntu-full-x64-qemu.pkr.hcl")

  def test_tatnet_bootstrap_and_cloud_init_contract_survive_upstream_merge
    template = File.read(TEMPLATE)
    pre = File.read(File.join(ROOT, "patches/ubuntu/files/pre-tatnet.sh"))
    runtime = File.read(File.join(ROOT, "patches/ubuntu/files/tatnet-runtime.sh"))
    assert_includes template, "custom/files/pre-tatnet.sh"
    assert_operator template.index("custom/files/tatnet-runtime.sh"), :>, template.index("custom/files/runner-user.sh")
    %w[write_files growpart resizefs runcmd scripts_user].each { |name| assert_match(/^  - #{name}$/, pre) }
    assert_includes runtime, "qemu-guest-agent"
    assert_includes runtime, "WantedBy=cloud-init.target"
    assert_includes runtime, "systemctl enable containerd.service docker.service"
    assert_includes runtime, "sudo -u runner /home/runner/bin/Runner.Listener --version"
  end

  def test_optional_ec2_units_do_not_abort_cloud_image_finalization
    script = File.read(File.join(ROOT, "patches/ubuntu/files/runner-user.sh"))
    assert_match(/for unit in [^\n]*hibinit-agent\.service[^\n]*; do\n  systemctl disable "\$unit" \|\| true\ndone/, script)
    refute_match(/for unit in [^\n]*grub-(?:common|initrd-fallback)\.service/, script)
    assert_includes script, "apt-get install -y chrony"
  end

  def test_qemu_keeps_the_common_apt_setup
    qemu = File.read(TEMPLATE)
    aws = File.read(File.join(ROOT, "patches/ubuntu/templates/ubuntu-full-x64.pkr.hcl"))
    %w[configure-apt.sh configure-dpkg-eatmydata.sh configure-apt-gzip-indexes.sh].each do |script|
      assert_includes qemu, script
      assert_includes aws, script
    end
  end
end
