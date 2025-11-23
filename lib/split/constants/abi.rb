# frozen_string_literal: true

module Split
  module Constants
    module Abi
      FACTORY = [
        {
          'inputs' => [
            {
              'components' => [
                { 'name' => 'recipients', 'type' => 'address[]' },
                { 'name' => 'allocations', 'type' => 'uint256[]' },
                { 'name' => 'totalAllocation', 'type' => 'uint256' },
                { 'name' => 'distributionIncentive', 'type' => 'uint16' },
              ],
              'name' => 'splitParams',
              'type' => 'tuple',
            },
            { 'name' => 'owner', 'type' => 'address' },
          ],
          'name' => 'predictDeterministicAddress',
          'outputs' => [{ 'name' => 'split', 'type' => 'address' }],
          'stateMutability' => 'view',
          'type' => 'function',
        },
        {
          'inputs' => [
            {
              'components' => [
                { 'name' => 'recipients', 'type' => 'address[]' },
                { 'name' => 'allocations', 'type' => 'uint256[]' },
                { 'name' => 'totalAllocation', 'type' => 'uint256' },
                { 'name' => 'distributionIncentive', 'type' => 'uint16' },
              ],
              'name' => 'splitParams',
              'type' => 'tuple',
            },
            { 'name' => 'owner', 'type' => 'address' },
            { 'name' => 'salt', 'type' => 'bytes32' },
          ],
          'name' => 'predictDeterministicAddress',
          'outputs' => [{ 'name' => 'split', 'type' => 'address' }],
          'stateMutability' => 'view',
          'type' => 'function',
        },
        {
          'inputs' => [
            {
              'components' => [
                { 'name' => 'recipients', 'type' => 'address[]' },
                { 'name' => 'allocations', 'type' => 'uint256[]' },
                { 'name' => 'totalAllocation', 'type' => 'uint256' },
                { 'name' => 'distributionIncentive', 'type' => 'uint16' },
              ],
              'name' => 'splitParams',
              'type' => 'tuple',
            },
            { 'name' => 'owner', 'type' => 'address' },
            { 'name' => 'creator', 'type' => 'address' },
            { 'name' => 'salt', 'type' => 'bytes32' },
          ],
          'name' => 'createSplitDeterministic',
          'outputs' => [{ 'name' => 'split', 'type' => 'address' }],
          'stateMutability' => 'payable',
          'type' => 'function',
        },
        {
          'inputs' => [
            {
              'components' => [
                { 'name' => 'recipients', 'type' => 'address[]' },
                { 'name' => 'allocations', 'type' => 'uint256[]' },
                { 'name' => 'totalAllocation', 'type' => 'uint256' },
                { 'name' => 'distributionIncentive', 'type' => 'uint16' },
              ],
              'name' => '_splitParams',
              'type' => 'tuple',
            },
            { 'name' => '_owner', 'type' => 'address' },
            { 'name' => '_salt', 'type' => 'bytes32' },
          ],
          'name' => 'isDeployed',
          'outputs' => [
            { 'name' => 'split', 'type' => 'address' },
            { 'name' => 'exists', 'type' => 'bool' },
          ],
          'stateMutability' => 'view',
          'type' => 'function',
        },
      ].freeze

      PUSH = <<~ABI
        [
          {
            "type": "function",
            "name": "distribute",
            "inputs": [
              {
                "name": "_split",
                "type": "tuple",
                "internalType": "struct SplitV2Lib.Split",
                "components": [
                  { "name": "recipients", "type": "address[]", "internalType": "address[]" },
                  { "name": "allocations", "type": "uint256[]", "internalType": "uint256[]" },
                  { "name": "totalAllocation", "type": "uint256", "internalType": "uint256" },
                  { "name": "distributionIncentive", "type": "uint16", "internalType": "uint16" }
                ]
              },
              { "name": "_token", "type": "address", "internalType": "address" },
              { "name": "_distributor", "type": "address", "internalType": "address" }
            ],
            "outputs": [],
            "stateMutability": "nonpayable"
          },
          {
            "type": "function",
            "name": "distribute",
            "inputs": [
              {
                "name": "_split",
                "type": "tuple",
                "internalType": "struct SplitV2Lib.Split",
                "components": [
                  { "name": "recipients", "type": "address[]", "internalType": "address[]" },
                  { "name": "allocations", "type": "uint256[]", "internalType": "uint256[]" },
                  { "name": "totalAllocation", "type": "uint256", "internalType": "uint256" },
                  { "name": "distributionIncentive", "type": "uint16", "internalType": "uint16" }
                ]
              },
              { "name": "_token", "type": "address", "internalType": "address" },
              { "name": "_distributeAmount", "type": "uint256", "internalType": "uint256" },
              { "name": "_performWarehouseTransfer", "type": "bool", "internalType": "bool" },
              { "name": "_distributor", "type": "address", "internalType": "address" }
            ],
            "outputs": [],
            "stateMutability": "nonpayable"
          },
          {
            "type": "function",
            "name": "getSplitBalance",
            "inputs": [
              { "name": "_token", "type": "address", "internalType": "address" }
            ],
            "outputs": [
              { "name": "splitBalance", "type": "uint256", "internalType": "uint256" },
              { "name": "warehouseBalance", "type": "uint256", "internalType": "uint256" }
            ],
            "stateMutability": "view"
          }
        ]
      ABI
    end
  end
end
