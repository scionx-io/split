# frozen_string_literal: true

# Simple test to check that the environment is set up properly for examples

require 'dotenv/load'

puts 'Environment variables check:'
puts "SEPOLIA_RPC_URL: #{ENV['SEPOLIA_RPC_URL'] ? 'SET' : 'NOT SET'}"
puts "OPERATOR_ADDRESS: #{ENV['OPERATOR_ADDRESS'] && ENV['OPERATOR_ADDRESS'] != '0xYourWalletAddress' ? 'SET' : 'DEFAULT/NOT SET'}"
puts "OPERATOR_PRIVATE_KEY: #{ENV['OPERATOR_PRIVATE_KEY'] && ENV['OPERATOR_PRIVATE_KEY'] != '0xYourPrivateKey' ? 'SET' : 'DEFAULT/NOT SET'}"

if ENV['SEPOLIA_RPC_URL'] && ENV['SEPOLIA_RPC_URL'] != ''
  puts "\nEnvironment looks good! You can run the examples now."
  puts 'Run: ruby create_split_example.rb'
else
  puts "\nPlease set your environment variables in the .env file"
end
