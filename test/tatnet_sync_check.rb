# Explicit integration check, invoked after bin/sync-local by the QEMU CI job.
require "json"
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

toolset = JSON.parse(File.read(File.join(release, "images/ubuntu/toolsets/toolset-2404.json")))
python = toolset.fetch("toolcache").find { |tool| tool.fetch("name") == "Python" }
unless python&.fetch("versions")&.include?("3.13.*")
  abort "Ubuntu 24.04 x64 must include Python 3.13 in the tool cache"
end
puts "Python 3.13 is included in the Ubuntu 24.04 x64 tool cache recipe"
