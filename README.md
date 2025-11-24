# Split::Rb

The `split-rb` gem provides a Ruby interface for interacting with the 0xSplits V2 protocol contracts. It enables creating, managing, and distributing funds through split contracts on various EVM-compatible blockchains.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'split-rb'
```

And then execute:
```bash
bundle install
```

Or install it yourself as:
```bash
gem install split-rb
```

## Configuration

The gem requires configuration for blockchain access and operator credentials. You'll need to implement the configuration module:

```ruby
module YourAppConfiguration
  def self.rpc_url(chain_id)
    # Return RPC URL for the given chain_id
    case chain_id
    when 1
      "https://mainnet.infura.io/v3/YOUR_PROJECT_ID"
    when 11155111
      "https://sepolia.infura.io/v3/YOUR_PROJECT_ID"
    # Add more chains as needed
    else
      raise "Unsupported chain: #{chain_id}"
    end
  end

  def self.operator_address
    # Return your operator's Ethereum address
    "0xYourOperatorAddress"
  end

  def self.operator_key
    # Return your operator's private key as an Eth::Key object
    Eth::Key.new(priv: "0xYourOperatorPrivateKey".gsub(/^0x/, ''))
  end
end
```

## Usage

### Creating a Split Contract

```ruby
# Example configuration for a split
config = {
  recipients: [
    { address: "0xRecipient1Address", percent_allocation: 60.0 },
    { address: "0xRecipient2Address", percent_allocation: 40.0 }
  ],
  distributor_fee_percent: 1.0,  # Optional: default is 0
  salt: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"  # Unique salt for deterministic deployment
}

# Create a new split on Ethereum mainnet (chain_id: 1)
result = Split::CreationService.create(
  chain_id: 1,
  config: config,
  config_module: YourAppConfiguration
)

puts "Transaction Hash: #{result[:transaction_hash]}"
puts "Split Address: #{result[:split_address]}"
puts "Block Number: #{result[:block_number]}"
```

### Distributing Funds

```ruby
# Assuming you have a split contract object and a token address
split_contract = # Your split contract object with chain, contract_address, recipients, etc.
token_address = "0xTokenContractAddress"  # Address of the token to distribute (use '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE' for native ETH)

result = Split::DistributionService.new.distribute(
  split_contract,
  token_address,
  YourAppConfiguration
)

puts "Distribution Transaction Hash: #{result[:transaction_hash]}"
puts "Distributions: #{result[:distributions]}"
```

### Fetching Split Data from GraphQL API

```ruby
# Fetch split data from 0xSplits GraphQL API
split_data = Split::GraphqlClient.fetch_split_data(
  "0xSplitContractAddress",
  1,  # chain_id
  "your_api_key"  # Optional, can also use SPLIT_API_KEY environment variable
)

puts split_data
```

### Available Contract Addresses and Supported Chains

```ruby
# Get supported chain IDs
supported_chains = Split::Contracts::SUPPORTED_CHAINS

# Get contract addresses
factory_address = Split::Contracts::FACTORY_ADDRESS
push_split_address = Split::Contracts::PUSH_SPLIT_ADDRESS
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ScionX/split.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).