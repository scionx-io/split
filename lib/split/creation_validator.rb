# frozen_string_literal: true

module Split
  class CreationValidator
    PERCENTAGE_TOLERANCE = (99.9..100.1)
    FEE_RANGE = (0.0..10.0)

    def initialize(config)
      @config = config
    end

    def validate!
      validate_recipients
      validate_salt
      validate_total_allocation
      validate_distributor_fee
      true
    end

    private

    attr_reader :config

    def validate_recipients
      recipients = config[:recipients]
      raise 'Recipients required' unless recipients&.any?

      recipients.each do |r|
        address = r[:address]
        raise 'Recipient address is required' if address.nil? || address.to_s.strip.empty?

        # Validate the Ethereum address format using eth gem
        begin
          Eth::Address.new(address)
          # The eth gem Address object should properly validate the address
        rescue ArgumentError => e
          raise "Invalid Ethereum address format: #{address} - #{e.message}"
        end
      end
    end

    def validate_salt
      raise 'Salt required' unless config[:salt]
    end

    def validate_total_allocation
      total = config[:recipients].sum { |r| r[:percent_allocation] }
      raise 'Total must be ~100%' unless PERCENTAGE_TOLERANCE.cover?(total)
    end

    def validate_distributor_fee
      fee = config[:distributor_fee_percent] || 0
      raise 'Distributor fee must be 0–10%' unless FEE_RANGE.cover?(fee)
    end
  end
end
