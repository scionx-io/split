# frozen_string_literal: true

module Split
  class Contracts
    # 0xSplits V2 Protocol Contract Addresses
    # @see https://docs.splits.org/core/split-v2#addresses
    # Note: Splits V2 uses CREATE2 deployment for consistent addresses across chains
    FACTORY_ADDRESS = '0x8E8eB0cC6AE34A38B67D5Cf91ACa38f60bc3Ecf4'
    PUSH_SPLIT_ADDRESS = '0x1e2086A7e84a32482ac03000D56925F607CCB708'
    PULL_FACTORY_ADDRESS = '0x6B9118074aB15142d7524E8c4ea8f62A3Bdb98f1'
    PULL_SPLIT_ADDRESS = '0x98254AeDb6B2c30b70483064367f0BA24ca86244'

    # Supported chains from official docs
    SUPPORTED_CHAINS = [
      1,       # Ethereum
      10,      # Optimism
      56,      # BSC
      100,     # Gnosis
      137,     # Polygon
      360,     # Shape
      480,     # World Chain
      2020,    # Ronin
      8453,    # Base
      42_161,   # Arbitrum
      42_220,   # Celo
      98_866,   # Plume
      7_777_777, # Zora
      11_155_111, # Sepolia (testnet)
      9998, # ScionX Testnet
    ].freeze

    CONTRACT_ADDRESSES = {
      # Push Split V2 Factory (same address on all chains)
      push_factory: SUPPORTED_CHAINS.to_h { |chain_id| [chain_id, FACTORY_ADDRESS] },

      # Pull Split V2 Factory (same address on all chains)
      pull_factory: SUPPORTED_CHAINS.to_h { |chain_id| [chain_id, PULL_FACTORY_ADDRESS] },

      # Push Split contracts (same address on all chains)
      push_split: SUPPORTED_CHAINS.to_h { |chain_id| [chain_id, PUSH_SPLIT_ADDRESS] },

      # Pull Split contracts (same address on all chains)
      pull_split: SUPPORTED_CHAINS.to_h { |chain_id| [chain_id, PULL_SPLIT_ADDRESS] },
    }.freeze
  end
end
