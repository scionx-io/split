# frozen_string_literal: true

module Split
  class DistributionService
    def distribute(split_contract, token_address, config_module = Split::Configuration)
      @config_module = config_module
      chain_id = split_contract.chain.id
      contract_address = split_contract.contract_address

      client = build_client(chain_id)
      contract = build_contract(contract_address)
      split_data = build_split_data_from_contract(split_contract)

      tx_hash, success = client.transact_and_wait(
        contract,
        'distribute',
        split_data,
        token_address,
        config_module.operator_address,
        sender_key: config_module.operator_key,
        gas_limit: 200_000,
        tx_value: 0,
      )

      unless success
        puts "Distribution failed: #{tx_hash}" if defined?(puts)
        raise "Distribution transaction failed: #{tx_hash}"
      end

      # Decode transfer events from successful transaction
      distributions = TransferEventDecoder.new(client).decode_transfer_events(tx_hash, token_address)
      puts "Distribution successful: #{tx_hash}" if defined?(puts)

      { transaction_hash: tx_hash, distributions: distributions }
    end

    private

    def build_client(chain_id)
      rpc_url = @config_module.rpc_url(chain_id)
      Eth::Client.create(rpc_url).tap do |c|
        c.max_priority_fee_per_gas = 30 * Eth::Unit::GWEI
        c.max_fee_per_gas = 50 * Eth::Unit::GWEI
      end
    end

    def build_contract(address)
      Eth::Contract.from_abi(
        name: 'Split',
        address: address,
        abi: JSON.parse(Split::Constants::Abi::PUSH),
      )
    end

    def build_split_data_from_contract(split_contract)
      [
        extract_addresses(split_contract.recipients),
        split_contract.allocations.map(&:to_i),
        split_contract.allocations.sum,
        (split_contract.distribution_incentive || 0).to_i,
      ]
    end

    def extract_addresses(recipients)
      # Handle different data structures to avoid calling .address on strings
      case recipients
      when Array
        if recipients.empty?
          []
        else
          first_recipient = recipients.first
          if first_recipient.is_a?(Hash)
            recipients.map { |r| r[:address] || r['address'] }
          elsif first_recipient.is_a?(String)
            recipients # Already an array of strings
          elsif first_recipient.respond_to?(:address)
            recipients.map(&:address)
          else
            # Fallback to try both hash access and method call safely
            recipients.map do |r|
              if r.respond_to?(:address)
                r.address
              elsif r.is_a?(Hash)
                r[:address] || r['address']
              else
                r.to_s # Convert to string as last resort
              end
            end
          end
        end
      else
        recipients.pluck('address') # fallback for AR relation
      end
    end
  end
end
