# frozen_string_literal: true

require_relative 'lib/split-contracts'

puts "Testing GraphQL client initialization..."

begin
  # This should trigger the error at the schema loading step
  client = Split::GraphqlClient.build_client("test_key")
  puts "Client built successfully"
rescue => e
  puts "Error building client: #{e.message}"
  puts "Backtrace: #{e.backtrace.join("\n")}"
end