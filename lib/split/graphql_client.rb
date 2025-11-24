# frozen_string_literal: true

require 'graphql/client'
require 'graphql/client/http'

module Split
  class GraphqlClient
    class << self
      attr_accessor :api_key
    end

    # Lazy-loaded HTTP adapter that uses the api_key at request time
    class SplitsHTTP < GraphQL::Client::HTTP
      def initialize
        super('https://api.splits.org/graphql')
      end

      def headers(_context)
        { 'Authorization' => "Bearer #{Split::GraphqlClient.api_key}" }
      end
    end

    HTTP = SplitsHTTP.new

    def self.ensure_initialized!
      return if @initialized

      raise 'Split::GraphqlClient.api_key must be set before use' if api_key.nil?

      @schema = GraphQL::Client.load_schema(HTTP)
      @client = GraphQL::Client.new(schema: @schema, execute: HTTP)

      # Parse query and assign to constant (required by graphql-client)
      const_set(:AccountQuery, @client.parse(<<~GRAPHQL))
        query($accountId: ID!, $chainId: String!) {
          account(id: $accountId, chainId: $chainId) {
            __typename
            id
            ... on Split {
              distributorFee
              recipients {
                account { id }
                ownership
              }
            }
          }
        }
      GRAPHQL

      @initialized = true
    end

    def self.client
      ensure_initialized!
      @client
    end

    def self.fetch_split_data(contract_address, chain_id)
      ensure_initialized!

      response = client.query(AccountQuery, variables: {
                                accountId: contract_address.downcase,
                                chainId: chain_id.to_s,
                              })

      account = response.data&.account
      return unless account&.__typename == 'Split'

      format_split_data(account)
    rescue StandardError => e
      puts "API fetch failed: #{e.message}" if defined?(puts)
      nil
    end

    def self.format_split_data(account)
      {
        recipients: account.recipients.map { |r| r.account.id },
        allocations: account.recipients.map { |r| r.ownership.to_i },
        distribution_incentive: account.distributor_fee.to_i,
      }
    end
    private_class_method :format_split_data
  end
end
