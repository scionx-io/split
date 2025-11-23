# Pimlico Gem Extraction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract Pimlico-related code from the split gem into a standalone `pimlico` gem that can be reused across projects.

**Architecture:** Create a new `pimlico` gem in `/Users/bolo/Documents/Code/ScionX/partners/pimlico/` containing the bundler client, ERC-4337 constants, EIP-7702 authorization, and UserOperation building utilities. The split gem will then depend on this new gem.

**Tech Stack:** Ruby 3.2+, eth gem for cryptographic operations

---

## Task 1: Create Pimlico Gem Directory Structure

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/`
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/lib/`
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/lib/pimlico/`

**Step 1: Create directory structure**

```bash
mkdir -p /Users/bolo/Documents/Code/ScionX/partners/pimlico/lib/pimlico
```

**Step 2: Verify directories exist**

```bash
ls -la /Users/bolo/Documents/Code/ScionX/partners/pimlico/
```

Expected: Directory listing showing `lib/` folder

---

## Task 2: Create Gemspec File

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/pimlico.gemspec`

**Step 1: Create the gemspec**

```ruby
# frozen_string_literal: true

require_relative 'lib/pimlico/version'

Gem::Specification.new do |spec|
  spec.name = 'pimlico'
  spec.version = Pimlico::VERSION
  spec.authors = ['ScionX']
  spec.email = ['contact@scionx.com']

  spec.summary = 'Ruby client for Pimlico bundler and paymaster API'
  spec.description = 'A Ruby gem for interacting with Pimlico ERC-4337 bundler and paymaster services, ' \
                     'including support for EIP-7702 sponsored transactions.'
  spec.homepage = 'https://github.com/ScionX/pimlico'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{lib}/**/*', 'README.md', 'LICENSE', 'CHANGELOG.md']
  end

  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_runtime_dependency 'eth', '~> 0.5'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
end
```

---

## Task 3: Create Version File

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/lib/pimlico/version.rb`

**Step 1: Create version file**

```ruby
# frozen_string_literal: true

module Pimlico
  VERSION = '0.1.0'
end
```

---

## Task 4: Create Constants File

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/lib/pimlico/constants.rb`

**Step 1: Create constants file (extracted from split/eip7702_constants.rb)**

```ruby
# frozen_string_literal: true

module Pimlico
  module Constants
    # ERC-4337 v0.7 EntryPoint (same on all chains)
    ENTRY_POINT_V07 = '0x0000000071727De22E5E9d8BAf0edAc6f37da032'

    # ERC-4337 v0.8 EntryPoint (required for EIP-7702 with SimpleSmartAccount)
    ENTRY_POINT_V08 = '0x4337084d9e255ff0702461cf8895ce9e3b5ff108'

    # SimpleSmartAccount implementation for EIP-7702 delegation (designed for v0.8)
    SIMPLE_ACCOUNT_7702 = '0xe6Cae83BdE06E4c305530e199D7217f42808555B'

    # EIP-7702 transaction type
    EIP7702_TX_TYPE = 0x04

    # Pimlico API base URL
    API_BASE_URL = 'https://api.pimlico.io/v2'
  end
end
```

---

## Task 5: Create EIP-7702 Authorization Helper

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/lib/pimlico/eip7702_auth.rb`

**Step 1: Create EIP-7702 authorization helper**

```ruby
# frozen_string_literal: true

module Pimlico
  class Eip7702Auth
    # Generate EIP-7702 authorization for an operator key
    #
    # @param operator_key [Eth::Key] The operator's private key
    # @param chain_id [Integer] The chain ID (must match target chain for Pimlico)
    # @param nonce [Integer] The EOA's transaction nonce (default 0 for new accounts)
    # @param delegate_address [String] The address to delegate to (default: SimpleSmartAccount)
    # @return [Hash] Authorization object for Pimlico
    def self.generate(operator_key, chain_id:, nonce: 0, delegate_address: nil)
      delegate_address ||= Constants::SIMPLE_ACCOUNT_7702

      # Convert address to raw 20-byte representation for RLP encoding
      address_bytes = [delegate_address[2..]].pack('H*')

      # EIP-7702 authorization message format:
      # keccak256(0x05 || rlp([chain_id, address, nonce]))
      authorization_data = Eth::Rlp.encode([chain_id, address_bytes, nonce])
      message = "\x05" + authorization_data
      message_hash = Eth::Util.keccak256(message)

      # Sign the authorization
      signature = operator_key.sign(message_hash)

      # Extract r, s, v from signature
      # Eth::Key.sign returns a hex string: r (64 chars) + s (64 chars) + v (2 chars)
      r = '0x' + signature[0...64]
      s = '0x' + signature[64...128]
      v_byte = signature[128..129].to_i(16)

      # EIP-7702 uses yParity (0 or 1) instead of v (27 or 28)
      y_parity = v_byte >= 27 ? v_byte - 27 : v_byte

      # Pimlico expects both v and yParity in the authorization
      {
        chainId: "0x#{chain_id.to_s(16)}",
        address: delegate_address,
        nonce: "0x#{nonce.to_s(16)}",
        v: "0x#{v_byte.to_s(16)}",
        yParity: "0x#{y_parity.to_s(16)}",
        r: r,
        s: s
      }
    end
  end
end
```

---

## Task 6: Create UserOperation Builder

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/lib/pimlico/user_operation_builder.rb`

**Step 1: Create UserOperation builder**

```ruby
# frozen_string_literal: true

module Pimlico
  class UserOperationBuilder
    # Dummy signature for gas estimation - SimpleAccount requires correct length
    # See: https://docs.pimlico.io/references/bundler/endpoints/eth_estimateUserOperationGas
    DUMMY_SIGNATURE = '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c'

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
        callData: call_data,
        callGasLimit: '0x0',
        verificationGasLimit: '0x0',
        preVerificationGas: '0x0',
        maxFeePerGas: '0x0',
        maxPriorityFeePerGas: '0x0',
        signature: DUMMY_SIGNATURE
      }

      user_op[:eip7702Auth] = authorization if authorization

      user_op
    end

    # Compute the UserOperation hash following ERC-4337 v0.8 specification (EIP-712)
    # For v0.8, we use EIP-712 typed data hashing
    def compute_hash(user_op, entry_point)
      # Build packed fields for EIP-712 typed data
      init_code = build_init_code(user_op)
      paymaster_and_data = build_paymaster_and_data(user_op)

      # Pack accountGasLimits: verificationGasLimit (uint128) || callGasLimit (uint128)
      verification_gas_limit = hex_to_int(user_op[:verificationGasLimit])
      call_gas_limit = hex_to_int(user_op[:callGasLimit])
      account_gas_limits = "0x#{pack_two_uint128(verification_gas_limit, call_gas_limit).unpack1('H*')}"

      # Pack gasFees: maxPriorityFeePerGas (uint128) || maxFeePerGas (uint128)
      max_priority_fee = hex_to_int(user_op[:maxPriorityFeePerGas])
      max_fee = hex_to_int(user_op[:maxFeePerGas])
      gas_fees = "0x#{pack_two_uint128(max_priority_fee, max_fee).unpack1('H*')}"

      # EIP-712 typed data structure for EntryPoint v0.8
      typed_data = {
        types: {
          EIP712Domain: [
            { name: 'name', type: 'string' },
            { name: 'version', type: 'string' },
            { name: 'chainId', type: 'uint256' },
            { name: 'verifyingContract', type: 'address' }
          ],
          PackedUserOperation: [
            { name: 'sender', type: 'address' },
            { name: 'nonce', type: 'uint256' },
            { name: 'initCode', type: 'bytes' },
            { name: 'callData', type: 'bytes' },
            { name: 'accountGasLimits', type: 'bytes32' },
            { name: 'preVerificationGas', type: 'uint256' },
            { name: 'gasFees', type: 'bytes32' },
            { name: 'paymasterAndData', type: 'bytes' }
          ]
        },
        primaryType: 'PackedUserOperation',
        domain: {
          name: 'ERC4337',
          version: '1',
          chainId: @chain_id,
          verifyingContract: entry_point
        },
        message: {
          sender: user_op[:sender],
          nonce: hex_to_int(user_op[:nonce]),
          initCode: init_code,
          callData: user_op[:callData],
          accountGasLimits: account_gas_limits,
          preVerificationGas: hex_to_int(user_op[:preVerificationGas]),
          gasFees: gas_fees,
          paymasterAndData: paymaster_and_data
        }
      }

      Eth::Eip712.hash(typed_data)
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
  end
end
```

---

## Task 7: Create Bundler Client

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/lib/pimlico/client.rb`

**Step 1: Create the main client**

```ruby
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Pimlico
  class Client
    attr_reader :api_key, :chain_id

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

    # Get paymaster data for sponsored transaction (ERC-7677 standard)
    # Params: [userOperation, entryPoint, chainId]
    # Use pm_sponsor_user_operation for sponsorship policies
    def pm_get_paymaster_data(user_op, entry_point)
      params = [user_op, entry_point, "0x#{@chain_id.to_s(16)}"]

      json_rpc_request(
        method: 'pm_getPaymasterData',
        params: params
      )
    end

    # Sponsor UserOperation with optional sponsorship policy (Pimlico-specific)
    # Params: [userOperation, entryPoint, context (optional)]
    # Returns gas estimates AND paymaster data
    def pm_sponsor_user_operation(user_op, entry_point, sponsorship_policy_id: nil)
      params = [user_op, entry_point]
      params << { sponsorshipPolicyId: sponsorship_policy_id } if sponsorship_policy_id

      json_rpc_request(
        method: 'pm_sponsorUserOperation',
        params: params
      )
    end

    # Send UserOperation to bundler
    # For EIP-7702, eip7702Auth should be included in the user_op object
    def eth_send_user_operation(user_op, entry_point)
      json_rpc_request(
        method: 'eth_sendUserOperation',
        params: [user_op, entry_point]
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

    # Validate sponsorship policies for a UserOperation
    # Returns which policies are valid for the given entryPoint
    def pm_validate_sponsorship_policies(user_op, entry_point, policy_ids)
      json_rpc_request(
        method: 'pm_validateSponsorshipPolicies',
        params: [user_op, entry_point, policy_ids]
      )
    end

    private

    def json_rpc_request(method:, params:)
      uri = URI("#{Constants::API_BASE_URL}/#{@chain_id}/rpc?apikey=#{@api_key}")

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
          { success: false, error: result['error']['message'], full_error: result['error'] }
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

---

## Task 8: Create Main Library Entry Point

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/lib/pimlico.rb`

**Step 1: Create main entry point**

```ruby
# frozen_string_literal: true

require 'eth'

require_relative 'pimlico/version'
require_relative 'pimlico/constants'
require_relative 'pimlico/client'
require_relative 'pimlico/eip7702_auth'
require_relative 'pimlico/user_operation_builder'

module Pimlico
  class Error < StandardError; end
end
```

---

## Task 9: Create Gemfile

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/Gemfile`

**Step 1: Create Gemfile**

```ruby
# frozen_string_literal: true

source 'https://rubygems.org'

gemspec
```

---

## Task 10: Create README

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/pimlico/README.md`

**Step 1: Create README**

```markdown
# Pimlico Ruby Client

A Ruby gem for interacting with Pimlico ERC-4337 bundler and paymaster services, including support for EIP-7702 sponsored transactions.

## Installation

Add this to your Gemfile:

```ruby
gem 'pimlico', path: '../pimlico'
```

## Usage

### Basic Client Setup

```ruby
require 'pimlico'

client = Pimlico::Client.new(
  api_key: 'your_pimlico_api_key',
  chain_id: 42161  # Arbitrum
)
```

### Get Gas Prices

```ruby
result = client.pimlico_get_user_operation_gas_price
if result[:success]
  gas_prices = result[:data]
  puts gas_prices['standard']['maxFeePerGas']
end
```

### Sponsor a UserOperation

```ruby
# Build a UserOperation
builder = Pimlico::UserOperationBuilder.new(
  sender: '0x...',
  chain_id: 42161
)

user_op = builder.build(
  call_data: '0x...',
  nonce: 0
)

# Sponsor with a policy
result = client.pm_sponsor_user_operation(
  user_op,
  Pimlico::Constants::ENTRY_POINT_V08,
  sponsorship_policy_id: 'sp_your_policy'
)
```

### EIP-7702 Authorization

```ruby
require 'eth'

operator_key = Eth::Key.new(priv: 'your_private_key')

auth = Pimlico::Eip7702Auth.generate(
  operator_key,
  chain_id: 42161,
  nonce: 0
)

# Include in UserOperation
user_op = builder.build(
  call_data: '0x...',
  nonce: 0,
  authorization: auth
)
```

## Constants

- `Pimlico::Constants::ENTRY_POINT_V07` - ERC-4337 v0.7 EntryPoint
- `Pimlico::Constants::ENTRY_POINT_V08` - ERC-4337 v0.8 EntryPoint (for EIP-7702)
- `Pimlico::Constants::SIMPLE_ACCOUNT_7702` - SimpleSmartAccount for delegation

## License

MIT
```

---

## Task 11: Update Split Gemspec to Depend on Pimlico

**Files:**
- Modify: `/Users/bolo/Documents/Code/ScionX/partners/split/split.gemspec`

**Step 1: Add pimlico dependency**

Change line 31 from:
```ruby
  spec.add_runtime_dependency "eth", "~> 0.5"
```

To:
```ruby
  spec.add_runtime_dependency "eth", "~> 0.5"
  spec.add_runtime_dependency "pimlico", path: "../pimlico"
```

Note: For local development, use path. For production, publish gem and use version.

---

## Task 12: Update Split Main Entry Point

**Files:**
- Modify: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split-contracts.rb`

**Step 1: Replace local requires with pimlico gem**

Change these lines:
```ruby
require_relative 'split/eip7702_constants'
require_relative 'split/pimlico_client'
require_relative 'split/user_operation_builder'
require_relative 'split/eip7702_auth'
```

To:
```ruby
require 'pimlico'
```

---

## Task 13: Update SponsoredDeploymentService to Use Pimlico Gem

**Files:**
- Modify: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/sponsored_deployment_service.rb`

**Step 1: Update class references**

Replace all occurrences of:
- `Split::PimlicoClient` → `Pimlico::Client`
- `Split::UserOperationBuilder` → `Pimlico::UserOperationBuilder`
- `Split::Eip7702Auth` → `Pimlico::Eip7702Auth`
- `Split::Eip7702Constants::ENTRY_POINT_V08` → `Pimlico::Constants::ENTRY_POINT_V08`
- `Split::Eip7702Constants::SIMPLE_ACCOUNT_7702` → `Pimlico::Constants::SIMPLE_ACCOUNT_7702`

The updated file should use `Pimlico::Client` instead of `PimlicoClient`, etc.

---

## Task 14: Delete Old Files from Split Gem

**Files:**
- Delete: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/pimlico_client.rb`
- Delete: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/user_operation_builder.rb`
- Delete: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/eip7702_auth.rb`
- Delete: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/eip7702_constants.rb`

**Step 1: Remove old files**

```bash
rm /Users/bolo/Documents/Code/ScionX/partners/split/lib/split/pimlico_client.rb
rm /Users/bolo/Documents/Code/ScionX/partners/split/lib/split/user_operation_builder.rb
rm /Users/bolo/Documents/Code/ScionX/partners/split/lib/split/eip7702_auth.rb
rm /Users/bolo/Documents/Code/ScionX/partners/split/lib/split/eip7702_constants.rb
```

---

## Task 15: Test the Integration

**Step 1: Install dependencies in pimlico gem**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/pimlico
bundle install
```

**Step 2: Test in Rails console**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails
bin/rails console
```

```ruby
# Test basic import
require 'pimlico'
Pimlico::Constants::ENTRY_POINT_V08

# Test client
client = Pimlico::Client.new(api_key: Rails.application.credentials.pimlico_api_key, chain_id: 42161)
client.pimlico_get_user_operation_gas_price

# Test full flow
User.first.create_wallet_and_split
```

Expected: All tests pass, UserOperation is successfully sponsored

---

## Task 16: Commit Changes

**Step 1: Commit pimlico gem**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/pimlico
git init
git add .
git commit -m "feat: initial pimlico gem with ERC-4337 bundler and EIP-7702 support"
```

**Step 2: Commit split gem changes**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/split
git add .
git commit -m "refactor: extract pimlico client to separate gem"
```
