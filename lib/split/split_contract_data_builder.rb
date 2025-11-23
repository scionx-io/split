# frozen_string_literal: true

module Split
  class SplitContractDataBuilder
    def initialize(split_contract)
      @split_contract = split_contract
    end

    def build_split_data
      recipients = @split_contract.recipients.pluck('address')
      allocations = @split_contract.recipients.map { |r| (r['percent_allocation'] * 10_000).to_i }

      {
        recipients: recipients,
        allocations: allocations,
        distribution_incentive: (@split_contract.distributor_fee_percent * 10_000).to_i,
      }
    end

    def build_split_tuple(data)
      [
        data[:recipients],
        data[:allocations].map(&:to_i),
        data[:allocations].sum,
        (data[:distribution_incentive] || 0).to_i,
      ]
    end
  end
end
