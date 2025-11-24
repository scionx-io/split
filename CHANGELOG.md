## [Unreleased]

### Added
- Support for Polygon mainnet (chain ID 137)
- Dynamic gas pricing for Polygon using Polygon gas station API to prevent "transaction underpriced" errors
- Configuration example updated to include Polygon RPC URL support

### Changed
- Renamed gem from 'split-contracts' to 'split-rb'
- Updated example to work with Polygon mainnet instead of Sepolia
- Improved gas fee handling for EVM-compatible chains