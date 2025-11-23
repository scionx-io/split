# frozen_string_literal: true

module Split
  class TransferEventDecoder
    def initialize(client)
      @client = client
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def decode_transfer_events(tx_hash, token_address)
      receipt = @client.eth_get_transaction_receipt(tx_hash)
      return [] unless receipt&.dig('result', 'logs')

      contract = build_erc20_contract(token_address)
      transfer_event = contract.events.first
      receipt['result']['logs'].filter_map do |log|
        next unless log['topics']&.first == "0x#{transfer_event.signature}"
        next unless log['address']&.downcase == token_address.downcase

        decoded = transfer_event.decode_params(log['topics'], log['data'])
        {
          from: decoded['from'],
          to: decoded['to'],
          value: decoded['value'],
          value_formatted: format_token_amount(decoded['value']),
        }
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    private

    def build_erc20_contract(token_address)
      transfer_abi = [{
        'anonymous' => false,
        'inputs' => [
          { 'indexed' => true, 'name' => 'from', 'type' => 'address' },
          { 'indexed' => true, 'name' => 'to', 'type' => 'address' },
          { 'indexed' => false, 'name' => 'value', 'type' => 'uint256' },
        ],
        'name' => 'Transfer',
        'type' => 'event',
      }]
      Eth::Contract.from_abi(abi: transfer_abi, address: token_address, name: 'Token')
    end

    def format_token_amount(value, decimals = 6)
      (value.to_f / (10**decimals)).round(decimals)
    end
  end
end
