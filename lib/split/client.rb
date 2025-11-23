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
      !!(@paymaster && @paymaster[:api_key])
    end

    # Get paymaster API key
    def paymaster_api_key
      @paymaster&.dig(:api_key)
    end

    # Get sponsorship policy ID
    def sponsorship_policy_id
      @paymaster&.dig(:sponsorship_policy_id)
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
        paymaster = @paymaster  # Capture the paymaster from the accessor
        config_module = Class.new do
          define_singleton_method(:rpc_url) { |cid| client.send(:rpc_url, cid) }
          define_singleton_method(:operator_address) { client.operator_address }
          define_singleton_method(:operator_key) { client.operator_key }
          define_singleton_method(:sponsorship_policy_id) { paymaster&.dig(:sponsorship_policy_id) }
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
