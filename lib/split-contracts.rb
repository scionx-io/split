# frozen_string_literal: true

require 'eth'
require 'securerandom'

require_relative 'split/version'
require_relative 'split/configuration'
require_relative 'split/contracts'
require_relative 'split/creation_service'
require_relative 'split/creation_validator'
require_relative 'split/distribution_service'
require_relative 'split/graphql_client'
require_relative 'split/split_contract_data_builder'
require_relative 'split/split_contract_data'
require_relative 'split/transfer_event_decoder'
require_relative 'split/constants/abi'
require 'pimlico'
require_relative 'split/sponsored_deployment_service'
require_relative 'split/client'

module Split
  class Error < StandardError; end

  class << self
    # @return [String, nil] Global operator address
    attr_accessor :operator_address

    # @return [String, nil] Global operator private key
    attr_accessor :operator_key

    # @return [Hash] RPC URLs by chain_id
    attr_accessor :rpc_urls

    # Configure global settings for Split
    #
    # @yield [self] Configuration block
    #
    # @example
    #   Split.configure do |config|
    #     config.operator_address = '0x...'
    #     config.operator_key = '0x...'
    #     config.rpc_urls = {
    #       137 => 'https://polygon-rpc.com',
    #       8453 => 'https://base-rpc.com'
    #     }
    #   end
    def configure
      yield self
    end

    # Initialize rpc_urls as empty hash
    def rpc_urls
      @rpc_urls ||= {}
    end
  end
end
