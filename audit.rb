#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'

puts '🔍 Running comprehensive code audit...'

# Install dependencies if not present
puts '📦 Installing dependencies...'
system('bundle', 'install', out: $stdout, err: :out) unless system('bundle', 'show', 'rubocop', out: '/dev/null', err: '/dev/null')

# Run RuboCop to identify style and maintainability issues
puts "\n📋 Running RuboCop audit..."
rubocop_result = system('bundle', 'exec', 'rubocop', '--config', '.rubocop.yml', '--format', 'progress', 'lib/')

# Check for potential security issues
puts "\n🔒 Running security audit..."
security_issues = []

Dir.glob('**/*.rb') do |file|
  next if file.start_with?('vendor/', 'tmp/', '.git/')
  next if File.directory?(file)

  content = File.read(file)
  
  # Check for potential security issues in the codebase
  content.each_line.with_index(1) do |line, line_num|
    if line.match?(/eval\s*\(/i)
      security_issues << "#{file}:#{line_num}: Potential eval() security risk"
    end
    
    if line.match?(/system\s*\([^'"]/) && !line.match?(/system\s*\(\s*['"][a-z0-9_-]+['"]\s*,/)
      security_issues << "#{file}:#{line_num}: Potential command injection risk"
    end
  end
end

if security_issues.empty?
  puts '✅ No major security issues detected.'
else
  puts '⚠️  Security issues found:'
  security_issues.each { |issue| puts "   #{issue}" }
end

# Check if RuboCop passed
if rubocop_result
  puts "\n✅ RuboCop audit passed! Most issues are fixable."
  puts "💡 Run 'bundle exec rubocop --config .rubocop.yml --auto-correct' to fix most issues automatically."
else
  puts "\n❌ RuboCop audit found issues. Run 'bundle exec rubocop --config .rubocop.yml' for details."
  puts "💡 Run 'bundle exec rubocop --config .rubocop.yml --auto-correct' to fix most issues automatically."
end

puts "\n📊 Audit completed."
