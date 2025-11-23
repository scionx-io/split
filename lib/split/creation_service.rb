# frozen_string_literal: true

module Split
  class CreationService
    PERCENTAGE_SCALE = 1_000_000
    PRIORITY_FEE = 30 * Eth::Unit::GWEI
    MAX_FEE = 50 * Eth::Unit::GWEI

    def self.create(chain_id:, config:, config_module: Split::Configuration, paymaster: nil)
      new(chain_id, config_module, paymaster).create(config)
    end

    def initialize(chain_id, config_module = Split::Configuration, paymaster = nil)
      @chain_id = chain_id
      @config_module = config_module
      @paymaster = paymaster
      @client = Eth::Client.create(@config_module.rpc_url(chain_id))
    end

    def create(config)
      validate!(config)
      contract = factory_contract
      args = split_args(config)
      split_addr = predict_address(config, contract)

      if deployed?(config, contract)
        already_deployed_result
      elsif @paymaster && @paymaster[:api_key]
        deploy_split_sponsored(contract, args, split_addr)
      else
        setup_gas
        deploy_split(contract, args, split_addr)
      end
    end

    private

    def validate!(config)
      CreationValidator.new(config).validate!
    end

    def setup_gas
      if @chain_id == 137
        setup_polygon_gas
      else
        @client.max_priority_fee_per_gas = PRIORITY_FEE
        @client.max_fee_per_gas = MAX_FEE
      end
    end

    def setup_polygon_gas
      require 'net/http'
      require 'json'

      gas_station_url = URI('https://gasstation.polygon.technology/v2')
      http = Net::HTTP.new(gas_station_url.host, gas_station_url.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(gas_station_url)
      response = http.request(request)

      if response.code == '200'
        data = JSON.parse(response.body)
        max_fee_gwei = (data.dig('fast', 'maxFee') || 80).ceil
        priority_fee_gwei = (data.dig('fast', 'maxPriorityFee') || 40).ceil

        @client.max_fee_per_gas = max_fee_gwei * Eth::Unit::GWEI
        @client.max_priority_fee_per_gas = priority_fee_gwei * Eth::Unit::GWEI
      else
        @client.max_priority_fee_per_gas = PRIORITY_FEE
        @client.max_fee_per_gas = MAX_FEE
      end
    rescue StandardError => e
      puts "Warning: Could not fetch Polygon gas prices: #{e.message}"
      @client.max_priority_fee_per_gas = PRIORITY_FEE
      @client.max_fee_per_gas = MAX_FEE
    end

    def deployed?(config, contract)
      params = build_params(config[:recipients], config[:distributor_fee_percent] || 0)
      addr, deployed = @client.call(contract, 'isDeployed', params, clean(@config_module.operator_address),
                                    clean(config[:salt]))
      @last_split_address = addr
      deployed
    end

    def already_deployed_result
      { transaction_hash: nil, block_number: nil, split_address: @last_split_address, already_existed: true }
    end

    def deploy_split(contract, args, split_addr)
      operator_key = Eth::Key.new(priv: @config_module.operator_key)
      tx_hash, success = @client.transact_and_wait(
        contract, 'createSplitDeterministic', *args,
        sender_key: operator_key, gas_limit: 300_000, tx_value: 0
      )
      raise "TX failed: #{tx_hash}" unless success

      receipt = @client.eth_get_transaction_receipt(tx_hash)
      { transaction_hash: tx_hash, block_number: receipt.dig('result', 'blockNumber'), split_address: split_addr }
    end

    def deploy_split_sponsored(_contract, args, split_addr)
      # Encode the factory call wrapped in SimpleSmartAccount.execute()
      call_data = encode_factory_call(args)

      # Initialize the sponsored deployment service
      sponsor_service = SponsoredDeploymentService.new(
        operator_key: @config_module.operator_key,
        paymaster_api_key: @paymaster[:api_key],
        chain_id: @chain_id,
        rpc_url: @config_module.rpc_url(@chain_id),
        sponsorship_policy_id: @config_module.sponsorship_policy_id
      )

      # Deploy the contract via sponsored UserOperation
      result = sponsor_service.deploy(call_data: call_data)

      if result[:success]
        {
          transaction_hash: result[:tx_hash],
          user_op_hash: result[:user_op_hash],
          split_address: split_addr,
          block_number: result.dig(:receipt, 'receipt', 'blockNumber'),
          already_existed: false,
          sponsored: true
        }
      else
        raise "Sponsored deployment failed: #{result[:error]}"
      end
    end

    def encode_factory_call(args)
      factory_address = Split::Contracts::CONTRACT_ADDRESSES[:push_factory][@chain_id]

      # Encode createSplitDeterministic((address[],uint256[],uint256,uint16),address,address,bytes32)
      function_signature = 'createSplitDeterministic((address[],uint256[],uint256,uint16),address,address,bytes32)'
      function_selector = Eth::Util.keccak256(function_signature)[0...4]

      split_params = args[0] # [recipients[], allocations[], totalAllocation, distributionIncentive]
      owner = args[1]
      creator = args[2]
      salt = args[3]

      encoded_params = Eth::Abi.encode(
        ['(address[],uint256[],uint256,uint16)', 'address', 'address', 'bytes32'],
        [split_params, owner, creator, hex_to_bytes32(salt)]
      )

      inner_call = function_selector + encoded_params

      # Wrap in SimpleSmartAccount.execute(address to, uint256 value, bytes calldata data)
      execute_signature = 'execute(address,uint256,bytes)'
      execute_selector = Eth::Util.keccak256(execute_signature)[0...4]

      execute_encoded = Eth::Abi.encode(
        ['address', 'uint256', 'bytes'],
        [factory_address, 0, inner_call]
      )

      '0x' + (execute_selector + execute_encoded).unpack1('H*')
    end

    def hex_to_bytes32(hex_str)
      hex_str = hex_str[2..] if hex_str.to_s.start_with?('0x')
      [hex_str.to_s.rjust(64, '0')].pack('H*')
    end

    def factory_contract
      addr = Split::Contracts::CONTRACT_ADDRESSES[:push_factory][@chain_id]
      Eth::Contract.from_abi(name: 'SplitFactory', address: addr, abi: Split::Constants::Abi::FACTORY)
    end

    def split_args(config)
      [
        build_params(config[:recipients], config[:distributor_fee_percent] || 0),
        clean(@config_module.operator_address),
        clean(@config_module.operator_address),
        clean(config[:salt]),
      ]
    end

    def build_params(recipients, distributor_fee = 0)
      addrs  = recipients.map { |r| clean(extract_address(r)) }
      allocs = recipients.map { |r| scaled_allocation(extract_allocation(r)) }

      [addrs, allocs, allocs.sum, scaled_fee(distributor_fee)]
    end

    def extract_address(recipient)
      case recipient
      when Hash
        addr = recipient[:address]
        # Ensure we always return a string representation
        addr.is_a?(String) ? addr : extract_address(addr)
      when String
        recipient # Return the string as-is
      else
        # Check if it's an object that has an address attribute/method
        if recipient.respond_to?(:[]) && recipient.respond_to?(:keys) # Likely a Hash-like object
          addr = recipient[:address]
          return addr.is_a?(String) ? addr : extract_address(addr) if addr
        end

        # Handle objects with an address method (like Eth::Address, Eth::Key)
        if recipient.respond_to?(:address) && !recipient.is_a?(String)
          addr = recipient.address
          # Make sure the result is a string; it might be an Eth::Address object or string
          return addr.is_a?(String) ? addr : addr.to_s
        end

        # Fallback: convert to string
        recipient.to_s
      end
    end

    def extract_allocation(recipient)
      case recipient
      when Hash
        recipient[:percent_allocation]
      when Numeric
        recipient
      else
        recipient.respond_to?(:percent_allocation) ? recipient.percent_allocation : recipient
      end
    end

    def predict_address(config, contract)
      res = @client.call(
        contract, 'predictDeterministicAddress',
        build_params(config[:recipients], config[:distributor_fee_percent] || 0),
        clean(@config_module.operator_address),
        clean(config[:salt])
      )
      Eth::Util.prefix_hex(res)
    end

    def scaled_allocation(percent)
      (percent * PERCENTAGE_SCALE / 100).to_i
    end

    def scaled_fee(percent)
      (percent * 10_000).to_i
    end

    def clean(val)
      Eth::Util.prefix_hex(Eth::Util.remove_hex_prefix(val.to_s))
    end
  end
end
