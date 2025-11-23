# frozen_string_literal: true

module Split
  class SponsoredDeploymentService
    MAX_RECEIPT_ATTEMPTS = 30
    RECEIPT_POLL_DELAY = 2

    def initialize(operator_key:, paymaster_api_key:, chain_id:, rpc_url:, sponsorship_policy_id: nil)
      @operator_key = Eth::Key.new(priv: operator_key)
      @operator_address = @operator_key.address.checksummed
      @chain_id = chain_id
      @rpc_url = rpc_url
      @eth_client = Eth::Client.create(rpc_url)
      @pimlico = Pimlico::Client.new(api_key: paymaster_api_key, chain_id: chain_id)
      @sponsorship_policy_id = sponsorship_policy_id
      @eip7702_auth = nil
    end

    # Deploy a contract via sponsored UserOperation
    # @param call_data [String] Encoded contract call (0x prefixed)
    # @return [Hash] { success: true/false, tx_hash: ..., error: ... }
    def deploy(call_data:)
      puts "[DEBUG] Starting sponsored deployment for #{@operator_address}"

      # 1. Get or generate EIP-7702 authorization
      authorization = get_or_create_authorization
      puts "[DEBUG] Step 1 - Authorization: #{authorization.inspect}"

      # 2. Get nonce from EntryPoint contract
      nonce = get_user_op_nonce
      puts "[DEBUG] Step 2 - Nonce: #{nonce}"

      # 3. Build UserOperation
      builder = Pimlico::UserOperationBuilder.new(sender: @operator_address, chain_id: @chain_id)
      user_op = builder.build(call_data: call_data, nonce: nonce, authorization: authorization)
      puts "[DEBUG] Step 3 - UserOp built: #{user_op.keys.inspect}"

      # 4. Get gas prices
      gas_price_result = @pimlico.pimlico_get_user_operation_gas_price
      puts "[DEBUG] Step 4 - Gas price result: #{gas_price_result.inspect}"
      return { success: false, error: "Gas price fetch failed: #{gas_price_result[:error]}" } unless gas_price_result[:success]

      gas_prices = gas_price_result[:data]
      user_op = update_gas_prices(user_op, gas_prices)
      puts "[DEBUG] Step 4 - Gas prices applied"

      # 5. Estimate gas (EIP-7702 requires EntryPoint v0.8)
      puts "[DEBUG] Step 5 - Estimating gas with UserOp: #{user_op.inspect}"
      gas_estimate_result = @pimlico.eth_estimate_user_operation_gas(
        user_op,
        Pimlico::Constants::ENTRY_POINT_V08
      )
      puts "[DEBUG] Step 5 - Gas estimate result: #{gas_estimate_result.inspect}"
      return { success: false, error: "Gas estimation failed: #{gas_estimate_result[:error]}" } unless gas_estimate_result[:success]

      merge_api_response(user_op, gas_estimate_result[:data])

      # 6. Validate and get paymaster sponsorship
      puts "[DEBUG] Step 6 - Sponsorship policy: #{@sponsorship_policy_id.inspect}"

      # First validate the policy if one is configured
      if @sponsorship_policy_id
        validation_result = @pimlico.pm_validate_sponsorship_policies(
          user_op,
          Pimlico::Constants::ENTRY_POINT_V08,
          [@sponsorship_policy_id]
        )
        puts "[DEBUG] Step 6a - Policy validation result: #{validation_result.inspect}"
      end

      # Get paymaster sponsorship using pm_sponsorUserOperation
      paymaster_result = @pimlico.pm_sponsor_user_operation(
        user_op,
        Pimlico::Constants::ENTRY_POINT_V08,
        sponsorship_policy_id: @sponsorship_policy_id
      )
      return { success: false, error: paymaster_result[:error] } unless paymaster_result[:success]

      merge_api_response(user_op, paymaster_result[:data])

      # 7. Sign the UserOperation
      user_op_hash_bytes = builder.compute_hash(user_op, Pimlico::Constants::ENTRY_POINT_V08)
      signature = @operator_key.sign(user_op_hash_bytes)
      user_op[:signature] = "0x#{signature}"

      # 8. Submit to bundler (eip7702Auth stays inside user_op)
      submit_result = @pimlico.eth_send_user_operation(
        user_op,
        Pimlico::Constants::ENTRY_POINT_V08
      )
      return { success: false, error: submit_result[:error] } unless submit_result[:success]

      user_op_hash = submit_result[:data]

      # 10. Wait for receipt
      wait_for_receipt(user_op_hash)
    end

    private

    def get_or_create_authorization
      return @eip7702_auth if @eip7702_auth

      # Get EOA nonce for authorization
      eoa_nonce = get_eoa_nonce
      # Pimlico requires chainId to match the target chain (not 0 for universal)
      @eip7702_auth = Pimlico::Eip7702Auth.generate(@operator_key, chain_id: @chain_id, nonce: eoa_nonce)
      @eip7702_auth
    end

    def get_eoa_nonce
      @eth_client.get_nonce(@operator_address)
    rescue StandardError
      0
    end

    # Get UserOperation nonce from EntryPoint contract
    # EntryPoint.getNonce(address sender, uint192 key) returns uint256
    def get_user_op_nonce
      entry_point = Pimlico::Constants::ENTRY_POINT_V08

      # Encode getNonce(address,uint192) call
      function_signature = 'getNonce(address,uint192)'
      function_selector = Eth::Util.keccak256(function_signature)[0...4]

      # Encode parameters: address (32 bytes) + uint192 key (32 bytes, key=0)
      encoded_params = Eth::Abi.encode(['address', 'uint192'], [@operator_address, 0])

      call_data = '0x' + (function_selector + encoded_params).unpack1('H*')

      result = @eth_client.eth_call({ to: entry_point, data: call_data })
      result['result'].to_i(16)
    rescue StandardError => e
      puts "[DEBUG] Failed to get nonce from EntryPoint: #{e.message}, using 0"
      0
    end

    def update_gas_prices(user_op, gas_prices)
      pricing = gas_prices['standard'] || gas_prices[:standard] || gas_prices.values.first
      user_op[:maxFeePerGas] = pricing['maxFeePerGas'] || pricing[:maxFeePerGas]
      user_op[:maxPriorityFeePerGas] = pricing['maxPriorityFeePerGas'] || pricing[:maxPriorityFeePerGas]
      user_op
    end

    # Robustly merge API response into user_op, handling string/symbol keys
    def merge_api_response(user_op, data)
      return unless data.is_a?(Hash)

      data.each do |key, value|
        sym_key = key.to_sym
        user_op[sym_key] = value if value
      end
    end

    def wait_for_receipt(user_op_hash)
      attempts = 0

      loop do
        result = @pimlico.eth_get_user_operation_receipt(user_op_hash)

        if result[:success] && result[:data]
          receipt = result[:data]
          tx_hash = receipt.dig('receipt', 'transactionHash') || user_op_hash
          return { success: true, tx_hash: tx_hash, user_op_hash: user_op_hash, receipt: receipt }
        end

        attempts += 1
        return { success: false, error: 'Timeout waiting for receipt' } if attempts >= MAX_RECEIPT_ATTEMPTS

        sleep(RECEIPT_POLL_DELAY)
      end
    end
  end
end