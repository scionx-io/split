# Pimlico Paymaster Integration for Split Gem

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Pimlico paymaster support to the Split gem so contract deployments can be gas-sponsored via ERC-4337 UserOperations.

**Architecture:** When `paymaster:` config is provided, `CreationService` routes to `SponsoredDeploymentService` which builds an ERC-4337 v0.7 UserOperation, gets gas sponsorship from Pimlico, signs with the operator's Eth::Key, and submits to the bundler. EIP-7702 authorization is auto-generated with `chain_id: 0` on first use.

**Tech Stack:** Ruby, eth.rb gem, Pimlico API (JSON-RPC), ERC-4337 v0.7, EIP-7702

---

## Task 1: Add EIP-7702 Constants

**Files:**
- Create: `lib/split/eip7702_constants.rb`
- Modify: `lib/split-contracts.rb` (add require)

**Step 1: Create constants file**

Create `lib/split/eip7702_constants.rb`:

```ruby
# frozen_string_literal: true

module Split
  module Eip7702Constants
    # ERC-4337 v0.7 EntryPoint (same on all chains)
    ENTRY_POINT_V07 = '0x0000000071727De22E5E9d8BAf0edAc6f37da032'

    # SimpleSmartAccount implementation for EIP-7702 delegation
    SIMPLE_ACCOUNT_7702 = '0xe6Cae83BdE06E4c305530e199D7217f42808555B'

    # EIP-7702 transaction type
    EIP7702_TX_TYPE = 0x04
  end
end
```

**Step 2: Add require to main file**

In `lib/split-contracts.rb`, add after line 14 (`require_relative 'split/constants/abi'`):

```ruby
require_relative 'split/eip7702_constants'
```

**Step 3: Verify file loads**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/split && ruby -r ./lib/split-contracts -e "puts Split::Eip7702Constants::ENTRY_POINT_V07"`

Expected: `0x0000000071727De22E5E9d8BAf0edAc6f37da032`

**Step 4: Commit**

```bash
git add lib/split/eip7702_constants.rb lib/split-contracts.rb
git commit -m "feat: add EIP-7702 and ERC-4337 constants"
```

---

## Task 2: Create PimlicoClient

**Files:**
- Create: `lib/split/pimlico_client.rb`
- Modify: `lib/split-contracts.rb` (add require)

**Step 1: Create Pimlico HTTP client**

Create `lib/split/pimlico_client.rb`:

```ruby
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Split
  class PimlicoClient
    BASE_URL = 'https://api.pimlico.io/v2'

    def initialize(api_key:, chain_id:)
      @api_key = api_key
      @chain_id = chain_id
    end

    # Estimate gas for a UserOperation
    def eth_estimate_user_operation_gas(user_op, entry_point)
      json_rpc_request(
        method: 'eth_estimateUserOperationGas',
        params: [user_op, entry_point]
      )
    end

    # Get paymaster data for sponsored transaction
    def pm_get_paymaster_data(user_op, entry_point, context: {})
      json_rpc_request(
        method: 'pm_getPaymasterData',
        params: [user_op, entry_point, context]
      )
    end

    # Send UserOperation to bundler
    def eth_send_user_operation(user_op, entry_point, authorization: nil)
      params = [user_op, entry_point]
      params << { authorization: authorization } if authorization

      json_rpc_request(
        method: 'eth_sendUserOperation',
        params: params
      )
    end

    # Get UserOperation receipt
    def eth_get_user_operation_receipt(user_op_hash)
      json_rpc_request(
        method: 'eth_getUserOperationReceipt',
        params: [user_op_hash]
      )
    end

    # Get current gas prices
    def pimlico_get_user_operation_gas_price
      json_rpc_request(
        method: 'pimlico_getUserOperationGasPrice',
        params: []
      )
    end

    # Get the next nonce for a sender
    def eth_get_user_operation_nonce(sender, key_type = 0)
      json_rpc_request(
        method: 'eth_getUserOperationNonce',
        params: [sender, "0x#{key_type.to_s(16)}"]
      )
    end

    private

    def json_rpc_request(method:, params:)
      uri = URI("#{BASE_URL}/#{@chain_id}/rpc?apikey=#{@api_key}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Post.new("#{uri.path}?#{uri.query}")
      request['Content-Type'] = 'application/json'

      payload = {
        jsonrpc: '2.0',
        id: rand(100_000),
        method: method,
        params: params
      }

      request.body = payload.to_json
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        result = JSON.parse(response.body)
        if result['error']
          { success: false, error: result['error']['message'] }
        else
          { success: true, data: result['result'] }
        end
      else
        { success: false, error: "HTTP error: #{response.code} - #{response.message}" }
      end
    rescue JSON::ParserError => e
      { success: false, error: "JSON parsing error: #{e.message}" }
    rescue StandardError => e
      { success: false, error: "Request error: #{e.message}" }
    end
  end
end
```

**Step 2: Add require to main file**

In `lib/split-contracts.rb`, add after the eip7702_constants require:

```ruby
require_relative 'split/pimlico_client'
```

**Step 3: Verify file loads**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/split && ruby -r ./lib/split-contracts -e "puts Split::PimlicoClient.new(api_key: 'test', chain_id: 42161).class"`

Expected: `Split::PimlicoClient`

**Step 4: Commit**

```bash
git add lib/split/pimlico_client.rb lib/split-contracts.rb
git commit -m "feat: add PimlicoClient for bundler/paymaster API"
```

---

## Task 3: Create UserOperationBuilder

**Files:**
- Create: `lib/split/user_operation_builder.rb`
- Modify: `lib/split-contracts.rb` (add require)

**Step 1: Create UserOperation builder**

Create `lib/split/user_operation_builder.rb`:

```ruby
# frozen_string_literal: true

module Split
  class UserOperationBuilder
    def initialize(sender:, chain_id:)
      @sender = sender
      @chain_id = chain_id
    end

    # Build a UserOperation for arbitrary contract call
    # @param call_data [String] Encoded contract call (0x prefixed)
    # @param nonce [Integer] UserOperation nonce
    # @param authorization [Hash, nil] EIP-7702 authorization
    def build(call_data:, nonce:, authorization: nil)
      user_op = {
        sender: @sender,
        nonce: to_hex(nonce),
        factory: nil,
        factoryData: '0x',
        callData: call_data,
        callGasLimit: '0x0',
        verificationGasLimit: '0x0',
        preVerificationGas: '0x0',
        maxFeePerGas: '0x0',
        maxPriorityFeePerGas: '0x0',
        paymaster: nil,
        paymasterVerificationGasLimit: '0x0',
        paymasterPostOpGasLimit: '0x0',
        paymasterData: '0x',
        signature: '0x'
      }

      user_op[:eip7702Authorization] = authorization if authorization

      user_op
    end

    # Compute the UserOperation hash following ERC-4337 v0.7 specification
    def compute_hash(user_op, entry_point)
      init_code = build_init_code(user_op)
      init_code_hash = keccak256_bytes(init_code)

      call_data_hash = keccak256_bytes(user_op[:callData])

      verification_gas_limit = hex_to_int(user_op[:verificationGasLimit])
      call_gas_limit = hex_to_int(user_op[:callGasLimit])
      account_gas_limits = pack_two_uint128(verification_gas_limit, call_gas_limit)

      max_priority_fee = hex_to_int(user_op[:maxPriorityFeePerGas])
      max_fee = hex_to_int(user_op[:maxFeePerGas])
      gas_fees = pack_two_uint128(max_priority_fee, max_fee)

      paymaster_and_data = build_paymaster_and_data(user_op)
      paymaster_and_data_hash = keccak256_bytes(paymaster_and_data)

      packed = Eth::Abi.encode(
        %w[address uint256 bytes32 bytes32 bytes32 uint256 bytes32 bytes32],
        [
          user_op[:sender],
          hex_to_int(user_op[:nonce]),
          init_code_hash,
          call_data_hash,
          account_gas_limits,
          hex_to_int(user_op[:preVerificationGas]),
          gas_fees,
          paymaster_and_data_hash
        ]
      )

      user_op_hash = Eth::Util.keccak256(packed)

      Eth::Util.keccak256(
        Eth::Abi.encode(
          %w[bytes32 address uint256],
          [user_op_hash, entry_point, @chain_id]
        )
      )
    end

    private

    def build_init_code(user_op)
      factory = user_op[:factory]
      factory_data = user_op[:factoryData] || '0x'

      if factory.nil? || factory == '0x' || factory == '0x0000000000000000000000000000000000000000'
        '0x'
      else
        factory_data_stripped = factory_data.start_with?('0x') ? factory_data[2..] : factory_data
        factory + factory_data_stripped
      end
    end

    def build_paymaster_and_data(user_op)
      paymaster = user_op[:paymaster]

      if paymaster.nil? || paymaster == '0x'
        '0x'
      else
        paymaster_bytes = hex_to_bytes(paymaster)
        verification_gas = hex_to_int(user_op[:paymasterVerificationGasLimit])
        post_op_gas = hex_to_int(user_op[:paymasterPostOpGasLimit])
        verification_gas_bytes = int_to_bytes(verification_gas, 16)
        post_op_gas_bytes = int_to_bytes(post_op_gas, 16)
        paymaster_data = user_op[:paymasterData] || '0x'
        paymaster_data_bytes = hex_to_bytes(paymaster_data)

        result = paymaster_bytes + verification_gas_bytes + post_op_gas_bytes + paymaster_data_bytes
        "0x#{result.unpack1('H*')}"
      end
    end

    def pack_two_uint128(high, low)
      high = high & ((1 << 128) - 1)
      low = low & ((1 << 128) - 1)
      combined = (high << 128) | low
      int_to_bytes(combined, 32)
    end

    def hex_to_int(hex_str)
      return 0 if hex_str.nil? || hex_str == '0x'

      hex_str = hex_str[2..] if hex_str.start_with?('0x')
      hex_str.to_i(16)
    end

    def to_hex(int_val)
      "0x#{int_val.to_s(16)}"
    end

    def hex_to_bytes(hex_str)
      return ''.b if hex_str.nil? || hex_str == '0x'

      hex_str = hex_str[2..] if hex_str.start_with?('0x')
      return ''.b if hex_str.empty?

      [hex_str].pack('H*')
    end

    def int_to_bytes(int_val, byte_length)
      hex = int_val.to_s(16).rjust(byte_length * 2, '0')
      [hex].pack('H*')
    end

    def keccak256_bytes(data)
      bytes = hex_to_bytes(data)
      Eth::Util.keccak256(bytes)
    end
  end
end
```

**Step 2: Add require to main file**

In `lib/split-contracts.rb`, add after pimlico_client require:

```ruby
require_relative 'split/user_operation_builder'
```

**Step 3: Verify file loads**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/split && ruby -r ./lib/split-contracts -e "puts Split::UserOperationBuilder.new(sender: '0x1234', chain_id: 42161).class"`

Expected: `Split::UserOperationBuilder`

**Step 4: Commit**

```bash
git add lib/split/user_operation_builder.rb lib/split-contracts.rb
git commit -m "feat: add UserOperationBuilder for ERC-4337 v0.7"
```

---

## Task 4: Create Eip7702Auth Helper

**Files:**
- Create: `lib/split/eip7702_auth.rb`
- Modify: `lib/split-contracts.rb` (add require)

**Step 1: Create EIP-7702 authorization helper**

Create `lib/split/eip7702_auth.rb`:

```ruby
# frozen_string_literal: true

module Split
  class Eip7702Auth
    # Generate EIP-7702 authorization for an operator key
    # Uses chain_id: 0 for universal validity across all chains
    #
    # @param operator_key [Eth::Key] The operator's private key
    # @param nonce [Integer] The EOA's transaction nonce (default 0 for new accounts)
    # @return [Hash] Authorization object for Pimlico
    def self.generate(operator_key, nonce: 0)
      # EIP-7702 authorization structure:
      # - chainId: 0 for universal validity
      # - address: SimpleSmartAccount implementation
      # - nonce: EOA's transaction nonce

      delegate_address = Eip7702Constants::SIMPLE_ACCOUNT_7702
      chain_id = 0 # Universal authorization

      # EIP-7702 authorization message format:
      # keccak256(0x05 || rlp([chain_id, address, nonce]))
      authorization_data = Eth::Rlp.encode([chain_id, delegate_address, nonce])
      message = "\x05" + authorization_data
      message_hash = Eth::Util.keccak256(message)

      # Sign the authorization
      signature = operator_key.sign(message_hash)

      # Extract r, s, v from signature
      # Eth::Key.sign returns a 65-byte signature: r (32) + s (32) + v (1)
      r = '0x' + signature[0...64]
      s = '0x' + signature[64...128]
      v_byte = signature[128..129].to_i(16)

      # EIP-7702 uses yParity (0 or 1) instead of v (27 or 28)
      y_parity = v_byte >= 27 ? v_byte - 27 : v_byte

      {
        chainId: "0x#{chain_id.to_s(16)}",
        address: delegate_address,
        nonce: "0x#{nonce.to_s(16)}",
        yParity: "0x#{y_parity.to_s(16)}",
        r: r,
        s: s
      }
    end
  end
end
```

**Step 2: Add require to main file**

In `lib/split-contracts.rb`, add after user_operation_builder require:

```ruby
require_relative 'split/eip7702_auth'
```

**Step 3: Verify file loads**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/split && ruby -r ./lib/split-contracts -e "puts Split::Eip7702Auth.class"`

Expected: `Class`

**Step 4: Commit**

```bash
git add lib/split/eip7702_auth.rb lib/split-contracts.rb
git commit -m "feat: add EIP-7702 authorization generator"
```

---

## Task 5: Create SponsoredDeploymentService

**Files:**
- Create: `lib/split/sponsored_deployment_service.rb`
- Modify: `lib/split-contracts.rb` (add require)

**Step 1: Create sponsored deployment orchestrator**

Create `lib/split/sponsored_deployment_service.rb`:

```ruby
# frozen_string_literal: true

module Split
  class SponsoredDeploymentService
    MAX_RECEIPT_ATTEMPTS = 30
    RECEIPT_POLL_DELAY = 2

    def initialize(operator_key:, paymaster_api_key:, chain_id:, rpc_url:)
      @operator_key = Eth::Key.new(priv: operator_key)
      @operator_address = @operator_key.address.checksummed
      @chain_id = chain_id
      @rpc_url = rpc_url
      @pimlico = PimlicoClient.new(api_key: paymaster_api_key, chain_id: chain_id)
      @eip7702_auth = nil
    end

    # Deploy a contract via sponsored UserOperation
    # @param call_data [String] Encoded contract call (0x prefixed)
    # @return [Hash] { success: true/false, tx_hash: ..., error: ... }
    def deploy(call_data:)
      # 1. Get or generate EIP-7702 authorization
      authorization = get_or_create_authorization

      # 2. Get nonce
      nonce_result = @pimlico.eth_get_user_operation_nonce(@operator_address)
      return { success: false, error: nonce_result[:error] } unless nonce_result[:success]

      nonce = nonce_result[:data].to_i(16)

      # 3. Build UserOperation
      builder = UserOperationBuilder.new(sender: @operator_address, chain_id: @chain_id)
      user_op = builder.build(call_data: call_data, nonce: nonce, authorization: authorization)

      # 4. Get gas prices
      gas_price_result = @pimlico.pimlico_get_user_operation_gas_price
      return { success: false, error: gas_price_result[:error] } unless gas_price_result[:success]

      gas_prices = gas_price_result[:data]
      user_op = update_gas_prices(user_op, gas_prices)

      # 5. Estimate gas
      gas_estimate_result = @pimlico.eth_estimate_user_operation_gas(
        user_op,
        Eip7702Constants::ENTRY_POINT_V07
      )
      return { success: false, error: gas_estimate_result[:error] } unless gas_estimate_result[:success]

      user_op.merge!(gas_estimate_result[:data].transform_keys(&:to_sym))

      # 6. Get paymaster sponsorship
      paymaster_result = @pimlico.pm_get_paymaster_data(
        user_op,
        Eip7702Constants::ENTRY_POINT_V07
      )
      return { success: false, error: paymaster_result[:error] } unless paymaster_result[:success]

      user_op.merge!(paymaster_result[:data].transform_keys(&:to_sym))

      # 7. Sign the UserOperation
      user_op_hash_bytes = builder.compute_hash(user_op, Eip7702Constants::ENTRY_POINT_V07)
      signature = @operator_key.sign(user_op_hash_bytes)
      user_op[:signature] = "0x#{signature}"

      # 8. Extract authorization before sending (Pimlico expects it separately)
      auth_to_send = user_op.delete(:eip7702Authorization)

      # 9. Submit to bundler
      submit_result = @pimlico.eth_send_user_operation(
        user_op,
        Eip7702Constants::ENTRY_POINT_V07,
        authorization: auth_to_send
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
      @eip7702_auth = Eip7702Auth.generate(@operator_key, nonce: eoa_nonce)
      @eip7702_auth
    end

    def get_eoa_nonce
      uri = URI(@rpc_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 5
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri.path.empty? ? '/' : uri.path)
      request['Content-Type'] = 'application/json'

      payload = {
        jsonrpc: '2.0',
        id: rand(100_000),
        method: 'eth_getTransactionCount',
        params: [@operator_address, 'latest']
      }

      request.body = payload.to_json
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        result = JSON.parse(response.body)
        result['result'] ? result['result'].to_i(16) : 0
      else
        0
      end
    rescue StandardError
      0
    end

    def update_gas_prices(user_op, gas_prices)
      pricing = gas_prices['standard'] || gas_prices[:standard] || gas_prices.values.first
      user_op[:maxFeePerGas] = pricing['maxFeePerGas'] || pricing[:maxFeePerGas]
      user_op[:maxPriorityFeePerGas] = pricing['maxPriorityFeePerGas'] || pricing[:maxPriorityFeePerGas]
      user_op
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
```

**Step 2: Add require to main file**

In `lib/split-contracts.rb`, add after eip7702_auth require:

```ruby
require_relative 'split/sponsored_deployment_service'
```

**Step 3: Verify file loads**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/split && ruby -r ./lib/split-contracts -e "puts Split::SponsoredDeploymentService.class"`

Expected: `Class`

**Step 4: Commit**

```bash
git add lib/split/sponsored_deployment_service.rb lib/split-contracts.rb
git commit -m "feat: add SponsoredDeploymentService for paymaster flow"
```

---

## Task 6: Modify Client to Accept Paymaster Config

**Files:**
- Modify: `lib/split/client.rb`

**Step 1: Update Client to accept paymaster option**

Replace entire `lib/split/client.rb` with:

```ruby
# frozen_string_literal: true

module Split
  class Client
    attr_reader :operator_address, :operator_key

    def initialize(operator_key: nil, rpc_urls: {}, paymaster: nil)
      @operator_key = operator_key || Split.operator_key
      @rpc_urls = rpc_urls.any? ? rpc_urls : Split.rpc_urls
      @paymaster = paymaster

      validate_credentials!
      derive_operator_address!
    end

    def splits
      @splits_accessor ||= SplitsAccessor.new(self, @paymaster)
    end

    # Check if paymaster is configured
    def paymaster_enabled?
      @paymaster && @paymaster[:api_key]
    end

    # Get paymaster API key
    def paymaster_api_key
      @paymaster&.dig(:api_key)
    end

    private

    def validate_credentials!
      raise ArgumentError, 'Operator key must be provided' if @operator_key.to_s.strip.empty?
    end

    def derive_operator_address!
      eth_key = Eth::Key.new(priv: @operator_key)
      @operator_address = eth_key.address.checksummed
    end

    def rpc_url(chain_id)
      @rpc_urls[chain_id] || raise(ArgumentError, "RPC URL for chain_id #{chain_id} not configured")
    end

    # Resource accessor for splits
    class SplitsAccessor
      def initialize(client, paymaster)
        @client = client
        @paymaster = paymaster
      end

      def create(chain_id:, recipients:, salt: nil, distributor_fee_percent: 0)
        salt ||= SecureRandom.hex(32)

        config = {
          recipients: recipients,
          salt: salt,
          distributor_fee_percent: distributor_fee_percent
        }

        # Build a config module that reads from client instance
        config_module = build_config_module

        result = Split::CreationService.create(
          chain_id: chain_id,
          config: config,
          config_module: config_module,
          paymaster: @paymaster
        )

        Response.new(result)
      end

      private

      def build_config_module
        client = @client
        config_module = Class.new do
          define_singleton_method(:rpc_url) { |cid| client.send(:rpc_url, cid) }
          define_singleton_method(:operator_address) { client.operator_address }
          define_singleton_method(:operator_key) { client.operator_key }
        end
        config_module
      end
    end

    # Response wrapper
    class Response
      attr_reader :data

      def initialize(data)
        @data = data
      end

      def success?
        @data && !@data[:split_address].nil?
      end

      def split_address
        @data[:split_address]
      end

      def transaction_hash
        @data[:transaction_hash]
      end

      def block_number
        @data[:block_number]
      end

      def already_existed?
        @data[:already_existed] == true
      end
    end
  end
end
```

**Step 2: Verify file loads**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/split && ruby -r ./lib/split-contracts -e "c = Split::Client.new(operator_key: '0x' + 'a' * 64, paymaster: { api_key: 'test' }); puts c.paymaster_enabled?"`

Expected: `true`

**Step 3: Commit**

```bash
git add lib/split/client.rb
git commit -m "feat: add paymaster config to Client"
```

---

## Task 7: Modify CreationService for Sponsored Path

**Files:**
- Modify: `lib/split/creation_service.rb`

**Step 1: Update CreationService to route to sponsored path**

Replace entire `lib/split/creation_service.rb` with:

```ruby
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

    def deploy_split_sponsored(contract, args, split_addr)
      # Encode the factory call
      call_data = encode_factory_call(contract, args)

      # Use sponsored deployment service
      service = SponsoredDeploymentService.new(
        operator_key: @config_module.operator_key,
        paymaster_api_key: @paymaster[:api_key],
        chain_id: @chain_id,
        rpc_url: @config_module.rpc_url(@chain_id)
      )

      result = service.deploy(call_data: call_data)

      if result[:success]
        {
          transaction_hash: result[:tx_hash],
          block_number: nil, # Could extract from receipt if needed
          split_address: split_addr,
          user_op_hash: result[:user_op_hash],
          sponsored: true
        }
      else
        raise "Sponsored deployment failed: #{result[:error]}"
      end
    end

    def encode_factory_call(contract, args)
      # Encode createSplitDeterministic call
      factory_address = Split::Contracts::CONTRACT_ADDRESSES[:push_factory][@chain_id]

      # ABI encode the function call
      # createSplitDeterministic(SplitParams splitParams, address owner, address creator, bytes32 salt)
      function_signature = 'createSplitDeterministic((address[],uint256[],uint256,uint16),address,address,bytes32)'
      function_selector = Eth::Util.keccak256(function_signature)[0...4]

      # args = [split_params_tuple, owner, creator, salt]
      split_params = args[0] # [recipients[], allocations[], totalAllocation, distributionIncentive]
      owner = args[1]
      creator = args[2]
      salt = args[3]

      # Encode tuple and other params
      encoded_params = Eth::Abi.encode(
        ['(address[],uint256[],uint256,uint16)', 'address', 'address', 'bytes32'],
        [split_params, owner, creator, hex_to_bytes32(salt)]
      )

      # Build full call: execute(address to, uint256 value, bytes calldata data)
      # SimpleSmartAccount.execute signature
      execute_signature = 'execute(address,uint256,bytes)'
      execute_selector = Eth::Util.keccak256(execute_signature)[0...4]

      inner_call = function_selector + encoded_params

      execute_encoded = Eth::Abi.encode(
        ['address', 'uint256', 'bytes'],
        [factory_address, 0, inner_call]
      )

      '0x' + (execute_selector + execute_encoded).unpack1('H*')
    end

    def hex_to_bytes32(hex_str)
      hex_str = hex_str[2..] if hex_str.start_with?('0x')
      [hex_str.rjust(64, '0')].pack('H*')
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
        clean(config[:salt])
      ]
    end

    def build_params(recipients, distributor_fee = 0)
      addrs = recipients.map { |r| clean(extract_address(r)) }
      allocs = recipients.map { |r| scaled_allocation(extract_allocation(r)) }

      [addrs, allocs, allocs.sum, scaled_fee(distributor_fee)]
    end

    def extract_address(recipient)
      case recipient
      when Hash
        addr = recipient[:address]
        addr.is_a?(String) ? addr : extract_address(addr)
      when String
        recipient
      else
        if recipient.respond_to?(:[]) && recipient.respond_to?(:keys)
          addr = recipient[:address]
          return addr.is_a?(String) ? addr : extract_address(addr) if addr
        end

        if recipient.respond_to?(:address) && !recipient.is_a?(String)
          addr = recipient.address
          return addr.is_a?(String) ? addr : addr.to_s
        end

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
```

**Step 2: Verify syntax**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/split && ruby -c lib/split/creation_service.rb`

Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add lib/split/creation_service.rb
git commit -m "feat: add sponsored deployment path to CreationService"
```

---

## Task 8: Integration Test

**Files:**
- Create: `test/sponsored_deployment_test.rb`

**Step 1: Create integration test file**

Create `test/sponsored_deployment_test.rb`:

```ruby
# frozen_string_literal: true

require_relative '../lib/split-contracts'

# Manual integration test - requires real API keys
# Run with: OPERATOR_KEY=0x... PIMLICO_API_KEY=... ruby test/sponsored_deployment_test.rb

operator_key = ENV['OPERATOR_KEY']
pimlico_api_key = ENV['PIMLICO_API_KEY']
arbitrum_rpc = ENV['ARBITRUM_RPC_URL'] || 'https://arb1.arbitrum.io/rpc'

unless operator_key && pimlico_api_key
  puts 'Usage: OPERATOR_KEY=0x... PIMLICO_API_KEY=... ruby test/sponsored_deployment_test.rb'
  exit 1
end

puts 'Creating Split client with paymaster...'
client = Split::Client.new(
  operator_key: operator_key,
  paymaster: { api_key: pimlico_api_key },
  rpc_urls: { 42_161 => arbitrum_rpc }
)

puts "Operator address: #{client.operator_address}"
puts "Paymaster enabled: #{client.paymaster_enabled?}"

# Test wallet addresses (replace with real ones for actual test)
user_wallet = '0x1234567890123456789012345678901234567890'
operator_wallet = client.operator_address

recipients = [
  { address: user_wallet, percent_allocation: 99.0 },
  { address: operator_wallet, percent_allocation: 1.0 }
]

puts "\nCreating split contract (sponsored)..."
puts "Recipients: #{recipients.inspect}"

begin
  result = client.splits.create(
    chain_id: 42_161,
    recipients: recipients,
    distributor_fee_percent: 0
  )

  if result.success?
    puts "\nSuccess!"
    puts "Split address: #{result.split_address}"
    puts "Transaction hash: #{result.transaction_hash}"
    puts "Already existed: #{result.already_existed?}"
    puts "Sponsored: #{result.data[:sponsored]}"
  else
    puts "\nFailed!"
    puts result.data.inspect
  end
rescue StandardError => e
  puts "\nError: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
```

**Step 2: Commit**

```bash
git add test/sponsored_deployment_test.rb
git commit -m "test: add sponsored deployment integration test"
```

---

## Task 9: Update Rails App Initializer

**Files:**
- Modify: `/Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails/config/initializers/split.rb`

**Step 1: Update Split client initialization**

The Rails app initializer should now include the paymaster config:

```ruby
# frozen_string_literal: true

SPLIT_CLIENT = Split::Client.new(
  operator_key: Rails.application.credentials.operator_private_key,
  paymaster: { api_key: Rails.application.credentials.pimlico_api_key },
  rpc_urls: {
    137 => Rails.application.credentials.polygon_rpc_url,
    8453 => Rails.application.credentials.base_rpc_url,
    42_161 => Rails.application.credentials.arbitrum_rpc_url
  }
)
```

**Step 2: Verify Rails app loads**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails && bin/rails runner "puts SPLIT_CLIENT.paymaster_enabled?"`

Expected: `true`

**Step 3: Commit (in Rails app)**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails
git add config/initializers/split.rb
git commit -m "feat: enable Pimlico paymaster for split contract deployments"
```

---

## Summary

After completing all tasks, the Split gem will:

1. Accept `paymaster: { api_key: "..." }` in `Client.new`
2. Auto-generate EIP-7702 authorization with `chain_id: 0` (universal)
3. Route to `SponsoredDeploymentService` when paymaster is configured
4. Fall back to direct transactions when no paymaster (backward compatible)

Usage:
```ruby
client = Split::Client.new(
  operator_key: "0x...",
  paymaster: { api_key: "pimlico_api_key" },
  rpc_urls: { 42161 => "https://arb1.arbitrum.io/rpc" }
)

# Deployment is now gas-sponsored automatically
result = client.splits.create(chain_id: 42161, recipients: [...])
```
