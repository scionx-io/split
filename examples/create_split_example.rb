# frozen_string_literal: true

# Example: Creating a new split contract

require 'bundler/setup'
Bundler.require

require 'dotenv/load'
require 'eth'  # For generating addresses if needed

require_relative 'configuration_example'

# Test that environment variables are set
unless ENV['POLYGON_RPC_URL']
  puts "Error: POLYGON_RPC_URL environment variable is not set"
  puts "Please set it in your .env file"
  exit 1
end

puts "Using RPC URL for Polygon: #{ENV['POLYGON_RPC_URL']}"

# Check if the private key is configured (the address will be derived from it)
if ENV['OPERATOR_PRIVATE_KEY'] && ENV['OPERATOR_PRIVATE_KEY'] != "0xYourPrivateKey" && !ENV['OPERATOR_PRIVATE_KEY'].empty?
  # Get the address from the configuration module (which derives it from the private key)
  operator_address = ExampleConfiguration.operator_address
  puts "Using operator address: #{operator_address} (derived from private key)"
else
  puts "Error: OPERATOR_PRIVATE_KEY not configured in .env file"
  puts "Please set OPERATOR_PRIVATE_KEY in your .env file"
  exit 1
end

# Configuration for the split
split_config = {
  recipients: [
    { address: "0x1234567890123456789012345678901234567890", percent_allocation: 70.0 },
    { address: "0x0987654321098765432109876543210987654321", percent_allocation: 30.0 }
  ],
  distributor_fee_percent: 1.0,  # Optional: 1% fee for the distributor
  salt: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"  # Unique salt for deterministic deployment
}

puts "Creating split contract on Polygon mainnet (chain_id: 137)..."

begin
  # Create a new split on Polygon mainnet (chain_id: 137)
  result = Split::CreationService.create(
    chain_id: 137,
    config: split_config,
    config_module: ExampleConfiguration
  )

  if result[:already_existed]
    puts "Split contract already exists!"
    puts "Address: #{result[:split_address]}"
  else
    puts "Split contract created successfully!"
    puts "Transaction Hash: #{result[:transaction_hash]}"
    puts "Contract Address: #{result[:split_address]}"
    puts "Block Number: #{result[:block_number]}"
  end
rescue => e
  puts "Error creating split: #{e.message}"
end