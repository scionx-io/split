# frozen_string_literal: true

# Example: Distributing funds to a split contract

require 'split'
require 'dotenv/load'
require 'ostruct'  # For OpenStruct
require 'eth'  # For generating addresses if needed
require_relative 'configuration_example'

# Mock split contract object structure (replace with your actual data structure)
class MockSplitContract
  attr_accessor :chain, :contract_address, :recipients, :allocations, :distribution_incentive

  def initialize(chain_id, contract_addr, recipients_data)
    @chain = OpenStruct.new(id: chain_id)
    @contract_address = contract_addr
    @recipients = recipients_data
    @allocations = recipients_data.map { |r| (r[:percent_allocation] * 10_000).to_i }
    @distribution_incentive = 100  # 1% as example
  end
end

# Test that environment variables are set
unless ENV['SEPOLIA_RPC_URL']
  puts "Error: SEPOLIA_RPC_URL environment variable is not set"
  puts "Please set it in your .env file"
  exit 1
end

# Check if the private key is configured (the address will be derived from it)
if ENV['OPERATOR_PRIVATE_KEY'] && ENV['OPERATOR_PRIVATE_KEY'] != "0xYourPrivateKey" && !ENV['OPERATOR_PRIVATE_KEY'].empty?
  # Get the address from the configuration module (which derives it from the private key)
  operator_address = ExampleConfiguration.operator_address
  puts "Using operator address: #{operator_address} (derived from private key)"
  puts "Chain ID: 11155111 (Sepolia)"
else
  puts "Error: OPERATOR_PRIVATE_KEY not configured in .env file"
  puts "Please set OPERATOR_PRIVATE_KEY in your .env file"
  exit 1
end

# Example usage
split_contract = MockSplitContract.new(
  11155111,  # Sepolia testnet
  "0xYourSplitContractAddress", 
  [
    { address: "0xRecipient1Address", percent_allocation: 70.0 },
    { address: "0xRecipient2Address", percent_allocation: 30.0 }
  ]
)

token_address = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"  # Use this for native ETH, or put an ERC20 token address

puts "Distributing funds to split contract on Sepolia testnet..."

begin
  distribution_service = Split::DistributionService.new
  result = distribution_service.distribute(
    split_contract,
    token_address,
    ExampleConfiguration
  )

  puts "Distribution completed successfully!"
  puts "Transaction Hash: #{result[:transaction_hash]}"
  puts "Distributions: #{result[:distributions]}"
rescue => e
  puts "Error during distribution: #{e.message}"
end