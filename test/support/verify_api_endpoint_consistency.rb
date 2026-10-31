# frozen_string_literal: true

# Standalone verification of the API endpoint consistency implementation (issue #944).
# Run without loading Rails: ruby test/support/verify_api_endpoint_consistency.rb
# Or with bundle: bundle exec ruby test/support/verify_api_endpoint_consistency.rb
#
# Option: pass --compliance to also scan the current API codebase and report violations
# (rswag specs using OAuth instead of API key, missing Minitest for API controllers,
# rswag specs with expect/assert).

require "yaml"

def project_root
  dir = File.dirname(File.expand_path(__FILE__))
  loop do
    return dir if File.exist?(File.join(dir, "AGENTS.md")) && File.directory?(File.join(dir, "docs", "llm-guides"))
    parent = File.dirname(dir)
    raise "Could not find project root (AGENTS.md + docs/llm-guides)" if parent == dir
    dir = parent
  end
end

def assert(condition, message)
  raise "FAIL: #{message}" unless condition
end

root = project_root
rule_path = File.join(root, ".cursor", "rules", "api-endpoint-consistency.mdc")
guide_path = File.join(root, "docs", "llm-guides", "api-endpoint-consistency.md")
agents_path = File.join(root, "AGENTS.md")

assert File.exist?(rule_path), "Rule file should exist at #{rule_path}"
rule_content = File.read(rule_path, encoding: "UTF-8")

frontmatter = rule_content.match(/\A---\r?\n(?<yaml>.*?)\r?\n---\r?\n(?<body>.*)\z/m)
assert frontmatter, "Rule must start with YAML frontmatter"
keys = YAML.parse(frontmatter[:yaml]).root.children.each_slice(2).map { |key, _value| key.value }
assert keys.sort == %w[alwaysApply description globs], "Rule must have exactly one description, globs and alwaysApply key"
metadata = YAML.safe_load(frontmatter[:yaml])
expected_globs = [
  "app/controllers/api/v1/**/*.rb",
  "spec/requests/api/v1/**/*.rb",
  "test/controllers/api/v1/**/*.rb"
]
assert metadata.fetch("globs").split(",").map(&:strip) == expected_globs, "Rule must retain exactly the API v1 globs"
assert metadata.fetch("alwaysApply") == false, "Rule must remain scoped, not always applied"
assert frontmatter[:body].strip == "@docs/llm-guides/api-endpoint-consistency.md", "Rule must import shared checklist"
assert File.exist?(guide_path), "Shared checklist should exist at #{guide_path}"
assert File.exist?(agents_path), "AGENTS.md should exist"
assert File.read(agents_path, encoding: "UTF-8").include?("docs/llm-guides/api-endpoint-consistency.md"),
       "AGENTS.md must link to the shared API checklist"

puts "OK: API endpoint consistency implementation verified (shared checklist + scoped adapter + AGENTS.md)."

if ARGV.include?("--compliance")
  puts "\n--- Compliance check (current APIs) ---"
  spec_dir = File.join(root, "spec", "requests", "api", "v1")
  test_dir = File.join(root, "test", "controllers", "api", "v1")
  app_controllers_dir = File.join(root, "app", "controllers", "api", "v1")

  rswag_oauth = []
  rswag_assertions = []
  missing_minitest = []

  if File.directory?(spec_dir)
    Dir.glob(File.join(spec_dir, "*_spec.rb")).each do |path|
      basename = File.basename(path, "_spec.rb")
      next if basename == "auth"
      content = File.read(path, encoding: "UTF-8")
      if content.include?("Doorkeeper") || content.include?("Bearer") || content.include?("access_token")
        rswag_oauth << "#{basename}_spec.rb"
      end
      rswag_assertions << "#{basename}_spec.rb" if content.include?("expect(") || content.include?("assert_")
    end
  end

  skip_controllers = %w[base_controller test_controller]
  if File.directory?(app_controllers_dir)
    Dir.glob(File.join(app_controllers_dir, "*_controller.rb")).each do |path|
      basename = File.basename(path, ".rb")
      next if skip_controllers.include?(basename)
      test_path = File.join(test_dir, "#{basename}_test.rb")
      missing_minitest << basename unless File.exist?(test_path)
    end
  end

  if rswag_oauth.any?
    puts "rswag using OAuth (should use API key per rule): #{rswag_oauth.join(", ")}"
  else
    puts "rswag auth: all specs use API key."
  end

  if rswag_assertions.any?
    puts "rswag with expect/assert (should be docs-only): #{rswag_assertions.join(", ")}"
  else
    puts "rswag: no expect/assert found (docs-only)."
  end

  if missing_minitest.any?
    puts "API v1 controllers missing Minitest: #{missing_minitest.join(", ")}"
  else
    puts "Minitest: all API v1 controllers have a test file."
  end

  puts "---"
end
