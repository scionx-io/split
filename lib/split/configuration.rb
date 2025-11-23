# frozen_string_literal: true

module Split
  module Configuration
    def self.rpc_url(chain_id)
      # This method should be implemented by the user of the gem
      # to return the appropriate RPC URL for the given chain_id
      raise NotImplementedError, 'BlockchainHelper.rpc_url must be implemented'
    end

    def self.operator_address
      # This method should be implemented by the user of the gem
      # to return the operator address
      raise NotImplementedError, 'Operator.address must be implemented'
    end

    def self.operator_key
      # This method should be implemented by the user of the gem
      # to return the operator private key
      raise NotImplementedError, 'Operator.key must be implemented'
    end
  end
end
