# frozen_string_literal: true

# Example configuration module implementation
# Replace this with your actual implementation

require 'split'
require 'dotenv/load'
require 'eth'

module ExampleConfiguration
  def self.rpc_url(chain_id)
    # Example RPC URL - replace with your actual RPC provider
    case chain_id
    when 1
      ENV['MAINNET_RPC_URL'] || 'https://mainnet.infura.io/v3/YOUR_PROJECT_ID'
    when 137       # Polygon mainnet
      ENV['POLYGON_RPC_URL'] || 'https://polygon.gateway.tenderly.co/44W1QYqeaaLtqmAyQwaTse'
    when 11155111  # Sepolia testnet
      ENV['SEPOLIA_RPC_URL'] || 'https://sepolia.infura.io/v3/YOUR_PROJECT_ID'
    when 8453      # Base mainnet
      ENV['BASE_RPC_URL'] || 'https://mainnet.base.org'
    else
      raise "Unsupported chain: #{chain_id}"
    end
  end

  def self.operator_address
    # Derive the address from the private key using eth.rb gem
    private_key = ENV['OPERATOR_PRIVATE_KEY']
    raise 'OPERATOR_PRIVATE_KEY must be set' unless private_key && !private_key.empty?
    
    key = Eth::Key.new(priv: private_key.gsub(/^0x/, ''))
    key.address.to_s  # Ensure it returns a string
  end

  def self.operator_key
    # Private key for the operator address (keep this secure!)
    private_key = ENV['OPERATOR_PRIVATE_KEY'] || '0xYourPrivateKey'
    Eth::Key.new(priv: private_key.gsub(/^0x/, ''))
  end
end
