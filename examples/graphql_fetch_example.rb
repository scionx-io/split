# frozen_string_literal: true

# Example: Fetching split data from 0xSplits GraphQL API

require 'split'
require 'dotenv/load'

split_address = "0xYourSplitContractAddress"
chain_id = 1  # Ethereum mainnet

puts "Fetching split data from 0xSplits API..."

begin
  # Fetch split data (API key can be provided as parameter or set as SPLIT_API_KEY environment variable)
  split_data = Split::GraphqlClient.fetch_split_data(
    split_address,
    chain_id,
    ENV['SPLIT_API_KEY']  # Optional: can also use SPLIT_API_KEY environment variable
  )

  if split_data
    puts "Split data retrieved successfully!"
    puts "Recipients: #{split_data[:recipients]}"
    puts "Allocations: #{split_data[:allocations]}"
    puts "Distribution Incentive: #{split_data[:distribution_incentive]}"
  else
    puts "No split data found or API request failed"
  end
rescue => e
  puts "Error fetching split data: #{e.message}"
end