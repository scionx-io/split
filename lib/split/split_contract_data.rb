# frozen_string_literal: true

module Split
  # Data object representing a split contract for distribution
  # Matches the interface expected by DistributionService
  class SplitContractData
    attr_reader :chain, :contract_address, :recipients, :allocations, :distribution_incentive

    def initialize(chain_id:, contract_address:, recipients:, allocations:, distribution_incentive: 0)
      @chain = Chain.new(chain_id)
      @contract_address = contract_address
      @recipients = recipients
      @allocations = allocations
      @distribution_incentive = distribution_incentive
    end

    # Nested class for chain to match expected interface (split_contract.chain.id)
    class Chain
      attr_reader :id

      def initialize(id)
        @id = id
      end
    end
  end
end
