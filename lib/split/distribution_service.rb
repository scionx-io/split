# frozen_string_literal: true

module Split
  class DistributionService
    def initialize(paymaster = nil)
      @paymaster = paymaster
    end

    def distribute(split_contract, token_address, config_module = Split::Configuration)
      @config_module = config_module
      chain_id = split_contract.chain.id
      contract_address = split_contract.contract_address

      split_data = build_split_data_from_contract(split_contract)

      if @paymaster && @paymaster[:api_key]
        distribute_sponsored(chain_id, contract_address, split_data, token_address)
      else
        distribute_regular(chain_id, contract_address, split_data, token_address)
      end
    end

    private

    def distribute_regular(chain_id, contract_address, split_data, token_address)
      client = build_client(chain_id)
      contract = build_contract(contract_address)

      operator_key = @config_module.operator_key
      operator_key = Eth::Key.new(priv: operator_key) if operator_key.is_a?(String)

      tx_hash, success = client.transact_and_wait(
        contract,
        'distribute',
        split_data,
        token_address,
        @config_module.operator_address,
        sender_key: operator_key,
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

    def distribute_sponsored(chain_id, contract_address, split_data, token_address)
      # Encode the distribute call wrapped in SimpleSmartAccount.execute()
      call_data = encode_distribute_call(contract_address, split_data, token_address)

      # Initialize the sponsored deployment service
      sponsor_service = SponsoredDeploymentService.new(
        operator_key: @config_module.operator_key,
        paymaster_api_key: @paymaster[:api_key],
        chain_id: chain_id,
        rpc_url: @config_module.rpc_url(chain_id),
        sponsorship_policy_id: @config_module.sponsorship_policy_id,
      )

      # Execute the distribution via sponsored UserOperation
      result = sponsor_service.deploy(call_data: call_data)

      if result[:success]
        # Decode transfer events from successful transaction
        client = build_client(chain_id)
        distributions = TransferEventDecoder.new(client).decode_transfer_events(result[:tx_hash], token_address)
        puts "Sponsored distribution successful: #{result[:tx_hash]}" if defined?(puts)

        {
          transaction_hash: result[:tx_hash],
          user_op_hash: result[:user_op_hash],
          distributions: distributions,
          sponsored: true,
        }
      else
        raise "Sponsored distribution failed: #{result[:error]}"
      end
    end

    def encode_distribute_call(contract_address, split_data, token_address)
      # Encode distribute((address[],uint256[],uint256,uint16),address,address)
      # split_data = [recipients[], allocations[], totalAllocation, distributionIncentive]
      function_signature = 'distribute((address[],uint256[],uint256,uint16),address,address)'
      function_selector = Eth::Util.keccak256(function_signature)[0...4]

      encoded_params = Eth::Abi.encode(
        ['(address[],uint256[],uint256,uint16)', 'address', 'address'],
        [split_data, token_address, @config_module.operator_address],
      )

      inner_call = function_selector + encoded_params

      # Wrap in SimpleSmartAccount.execute(address to, uint256 value, bytes calldata data)
      execute_signature = 'execute(address,uint256,bytes)'
      execute_selector = Eth::Util.keccak256(execute_signature)[0...4]

      execute_encoded = Eth::Abi.encode(
        %w[address uint256 bytes],
        [contract_address, 0, inner_call],
      )

      "0x#{(execute_selector + execute_encoded).unpack1('H*')}"
    end

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
