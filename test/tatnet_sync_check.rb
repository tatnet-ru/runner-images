# Explicit integration check, invoked after bin/sync-local by the QEMU CI job.
require "yaml"
root = File.expand_path("..", __dir__)
release = File.join(root, "releases/ubuntu24/x64")
template = File.read(File.join(root, "patches/ubuntu/templates/ubuntu-full-x64-qemu.pkr.hcl"))
paths = template.scan(/\$\{path.root\}([^"\n]+)/).flatten
paths.reject! { |p| p.include?("${") }
missing = paths.reject { |p| File.exist?(File.expand_path("images/ubuntu/templates" + p, release)) }
config = YAML.load_file(File.join(root, "config.yml"))
image = config.fetch("images").find { |i| i.fetch("id") == "ubuntu24-full-x64" }
image.fetch("install_scripts").each do |script|
  path = File.join(release, "images/ubuntu/scripts/build", script)
  missing << path unless File.file?(path)
end
abort "QEMU build inputs missing: #{missing.join(', ')}" unless missing.empty?
puts "QEMU inputs verified: #{paths.size} paths and #{image.fetch('install_scripts').size} configured installers"
