# frozen_string_literal: true

require 'graphql/client'
require 'graphql/client/http'

module Split
  class GraphqlClient
    def self.build_client(api_key = nil)
      api_key ||= ENV.fetch('SPLIT_API_KEY', nil)

      # Create a HTTP adapter that adds authorization header
      http = GraphQL::Client::HTTP.new('https://api.splits.org/graphql')

      # Create wrapper to add header
      wrapper = Object.new
      def wrapper.setup(http_obj, auth_key)
        @http = http_obj
        @api_key = auth_key
        self
      end
      wrapper.setup(http, api_key)

      class << wrapper
        def headers(context)
          result = @http.headers(context) || {}
          if @api_key
            result['Authorization'] = "Bearer #{@api_key}"
          end
          result
        end

        def execute(query, context = nil)
          # The GraphQL client may call with different signatures during schema loading
          if context
            @http.execute(query, context)
          else
            @http.execute(query)
          end
        end

        def schema_id
          @http.schema_id
        end
      end

      schema = GraphQL::Client.load_schema(wrapper)
      GraphQL::Client.new(schema: schema, execute: wrapper)
    end

    def self.fetch_split_data(contract_address, chain_id, api_key = nil)
      client = build_client(api_key)
      account_query = client.parse <<~GRAPHQL
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

      response = client.query(account_query, variables: {
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
