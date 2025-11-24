# Add Distribute Method to Split Client

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `distribute` method to `SPLIT_CLIENT.splits` so consumers can distribute funds with a single call: `SPLIT_CLIENT.splits.distribute(contract_address:, chain_id:, token_address:)`

**Architecture:** The `SplitsAccessor` class will get a new `distribute` method that:
1. Fetches split data (recipients, allocations, distributor fee) from Split's GraphQL API
2. Builds a data object matching `DistributionService` expectations
3. Calls `DistributionService.distribute` with the client's config module

**Tech Stack:** Ruby, eth.rb gem, GraphQL API

---

## Task 1: Add DistributeResponse Class

**Files:**
- Modify: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/client.rb:94-121`

**Step 1: Add DistributeResponse class after the existing Response class**

Add this class inside the `Client` class, after the `Response` class (around line 121):

```ruby
# Response wrapper for distribute operations
class DistributeResponse
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def success?
    @data && !@data[:transaction_hash].nil?
  end

  def transaction_hash
    @data[:transaction_hash]
  end

  def distributions
    @data[:distributions] || []
  end
end
```

**Step 2: Verify syntax**

Run: `ruby -c /Users/bolo/Documents/Code/ScionX/partners/split/lib/split/client.rb`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/split
git add lib/split/client.rb
git commit -m "feat: add DistributeResponse class for distribute operations"
```

---

## Task 2: Add SplitContractData Class

This is a simple data object to hold split contract data for the DistributionService.

**Files:**
- Create: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/split_contract_data.rb`
- Modify: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split-contracts.rb`

**Step 1: Create the SplitContractData class**

Create file `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/split_contract_data.rb`:

```ruby
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
```

**Step 2: Add require to split-contracts.rb**

In `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split-contracts.rb`, add after line 13 (after `split_contract_data_builder`):

```ruby
require_relative 'split/split_contract_data'
```

**Step 3: Verify syntax**

Run: `ruby -c /Users/bolo/Documents/Code/ScionX/partners/split/lib/split/split_contract_data.rb`
Expected: `Syntax OK`

**Step 4: Commit**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/split
git add lib/split/split_contract_data.rb lib/split-contracts.rb
git commit -m "feat: add SplitContractData class for distribution"
```

---

## Task 3: Add distribute Method to SplitsAccessor

**Files:**
- Modify: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/client.rb:51-92`

**Step 1: Add the distribute method to SplitsAccessor**

Add this method inside the `SplitsAccessor` class, after the `create` method (around line 77, before `private`):

```ruby
def distribute(contract_address:, chain_id:, token_address:)
  # Fetch split data from GraphQL API
  split_data = Split::GraphqlClient.fetch_split_data(contract_address, chain_id)

  unless split_data
    raise ArgumentError, "Could not fetch split data for #{contract_address} on chain #{chain_id}"
  end

  # Build split contract data object
  split_contract = Split::SplitContractData.new(
    chain_id: chain_id,
    contract_address: contract_address,
    recipients: split_data[:recipients],
    allocations: split_data[:allocations],
    distribution_incentive: split_data[:distribution_incentive]
  )

  # Build config module from client
  config_module = build_config_module

  # Execute distribution
  result = Split::DistributionService.new.distribute(
    split_contract,
    token_address,
    config_module
  )

  DistributeResponse.new(result)
end
```

**Step 2: Verify syntax**

Run: `ruby -c /Users/bolo/Documents/Code/ScionX/partners/split/lib/split/client.rb`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/split
git add lib/split/client.rb
git commit -m "feat: add distribute method to SplitsAccessor"
```

---

## Task 4: Update DistributionService to Use Config Module for RPC

The current `DistributionService.build_client` uses `BlockchainHelper.rpc_url` which may not exist. Update it to use the config_module.

**Files:**
- Modify: `/Users/bolo/Documents/Code/ScionX/partners/split/lib/split/distribution_service.rb:5-43`

**Step 1: Update distribute method signature and build_client**

Replace the `distribute` method and `build_client` method:

```ruby
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
```

**Step 2: Verify syntax**

Run: `ruby -c /Users/bolo/Documents/Code/ScionX/partners/split/lib/split/distribution_service.rb`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/split
git add lib/split/distribution_service.rb
git commit -m "refactor: use config_module for RPC URL in DistributionService"
```

---

## Task 5: Update Bridge App's DistributeFundsJob

Now that the gem has a simple `distribute` method, simplify the bridge app's job.

**Files:**
- Modify: `/Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails/app/jobs/distribute_funds_job.rb`

**Step 1: Replace the entire file with simplified version**

```ruby
class DistributeFundsJob < ApplicationJob
  queue_as :default

  # Token addresses for Arbitrum
  ARBITRUM_USDC_ADDRESS = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831".freeze
  NATIVE_ETH_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE".freeze

  def perform(user_id, currency, transaction_id)
    user = User.find(user_id)
    transaction = Transaction.find(transaction_id)
    split_contract = user.split_contract

    unless split_contract
      Rails.logger.info "No split contract found for user #{user_id}, skipping distribution"
      return
    end

    Rails.logger.info "Distributing funds from split contract: #{split_contract.contract_address} for user: #{user.id}"

    token_address = token_address_for(currency)

    begin
      result = SPLIT_CLIENT.splits.distribute(
        contract_address: split_contract.contract_address,
        chain_id: split_contract.chain_id,
        token_address: token_address
      )

      Rails.logger.info "Distribution successful: #{result.transaction_hash}"

      transaction.update!(
        metadata: transaction.metadata.merge({
          distribution_tx_hash: result.transaction_hash,
          distribution_result: result.distributions
        })
      )
    rescue => e
      Rails.logger.error "Failed to distribute funds: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"

      transaction.update!(
        metadata: transaction.metadata.merge({
          distribution_error: e.message
        })
      )

      raise e
    end
  end

  private

  def token_address_for(currency)
    case currency
    when "USD"
      ARBITRUM_USDC_ADDRESS
    when "ETH"
      NATIVE_ETH_ADDRESS
    else
      ARBITRUM_USDC_ADDRESS
    end
  end
end
```

**Step 2: Delete the SplitContractData model from bridge app (no longer needed)**

Delete file: `/Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails/app/models/split_contract_data.rb`

**Step 3: Update DepositHandler to pass correct arguments**

In `/Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails/app/services/webhooks/deposit_handler.rb`, ensure line 50 is:

```ruby
DistributeFundsJob.perform_later(virtual_account.user.id, currency, transaction.id)
```

**Step 4: Run tests**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails && bin/rails test`
Expected: All tests pass

**Step 5: Commit**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails
git add app/jobs/distribute_funds_job.rb app/services/webhooks/deposit_handler.rb
git rm app/models/split_contract_data.rb
git commit -m "refactor: simplify DistributeFundsJob to use SPLIT_CLIENT.splits.distribute"
```

---

## Task 6: Ensure SplitContract Model Has chain_id

The bridge app's `SplitContract` model needs a `chain_id` column for the distribute call.

**Files:**
- Check: `/Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails/db/schema.rb`

**Step 1: Check if chain_id exists on split_contracts table**

Look for `chain_id` in the `split_contracts` table definition in schema.rb.

If it doesn't exist, create a migration:

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails
bin/rails generate migration AddChainIdToSplitContracts chain_id:integer
```

Then edit the migration to set a default:

```ruby
class AddChainIdToSplitContracts < ActiveRecord::Migration[8.0]
  def change
    add_column :split_contracts, :chain_id, :integer, default: 42161  # Arbitrum
  end
end
```

**Step 2: Run migration**

Run: `cd /Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails && bin/rails db:migrate`

**Step 3: Commit**

```bash
cd /Users/bolo/Documents/Code/ScionX/partners/bridge/bridge_whatsapp_rails
git add db/migrate/*add_chain_id* db/schema.rb
git commit -m "feat: add chain_id to split_contracts table"
```

---

## Summary

After completing all tasks, the usage will be:

```ruby
# In bridge app
SPLIT_CLIENT.splits.distribute(
  contract_address: "0x...",
  chain_id: 42161,
  token_address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
)
```

This encapsulates all the complexity (fetching split data, building objects, calling blockchain) inside the gem.
