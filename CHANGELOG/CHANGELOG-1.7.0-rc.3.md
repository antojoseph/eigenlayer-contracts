# v1.7.0-rc.3 Multi Chain

The below release notes cover the updated version 

*Note: v1.7.0-rc.1 was the final redistribution release on top of multichain. v1.7.0-rc.2 is the final MOOCOW release on top of multichain.*

## Release Manager

@ypatil12 @eigenmikem

## Highlights

🚀 New Features
- The `ECDSACertificateVerifier` and `BN254CertficateVerifier` have new storage/introspection for checking a reference timestamp: `isReferenceTimestampSet`

⛔ Breaking Changes
- The preprod/testnet contracts have been redeployed with fresh addresses since this upgrade is *not* upgrade safe from `v1.7.0-rc.0`
- `CrossChainRegistry`: All references to AVSs setting transport destinations have been removed. OperatorSets will be transported to *all* supported chains. See [PR #1512](https://github.com/Layr-Labs/eigenlayer-contracts/pull/1512)
    - `createGenerationReservation` no longer takes in a list of `chainIDs`
    - `addTransportDestinations` and `removeTransportDestinations` have been removed
    - `getActiveTransportReservations` and `getTransportDestinations(operatorSet)` have been removed

🛠️ Security Fixes
- In the `OperatorTableCalculator`, we now hard-code the `Generator`'s table root and reference timestamp. See [PR #1537](https://github.com/layr-labs/eigenlayer-contracts/pull/1537)

🔧 Improvements
- The `ECDSACertificateVerifier` now has a `calculateCertificateDigestBytes`, which returns the non-hashed bytes of the digest. See [PR #1542](https://github.com/layr-labs/eigenlayer-contracts/pull/1542)
- Clarify stakes are stake weights

🐛 Bug Fixes
- Allow 0 staleness periods for the `ECDSACertificateVerifier`. See [PR #1540](https://github.com/layr-labs/eigenlayer-contracts/pull/1540)
- Allow ECDSA certificates to be valid even if not on the latest reference timestamp to match BN254 certificates. See [PR #1540](https://github.com/layr-labs/eigenlayer-contracts/pull/1540) 
- Added a new parameter: `TableUpdateCadence` to the `CrossChainRegistry`. We now enforce that `maxStalenessPeriod` is >= `TableUpdateCadence` to prevent bricking Certificate Verification. See [PR #1536](https://github.com/layr-labs/eigenlayer-contracts/pull/1536)

## Changelog

- refactor: remove transport interface [PR #1512](https://github.com/Layr-Labs/eigenlayer-contracts/pull/1512)
- chore: stake -> stake weight [PR# 1541] https://github.com/Layr-Labs/eigenlayer-contracts/pull/1541
- feat: add calculateCertificateDigestBytes to ECDSA cert verifier [PR #1542](https://github.com/layr-labs/eigenlayer-contracts/pull/1542)
- chore: symmetric `BN254` and `ECDSA` checks [PR #1540](https://github.com/layr-labs/eigenlayer-contracts/pull/1540)
- feat: cleaner generator updates [PR #1537](https://github.com/layr-labs/eigenlayer-contracts/pull/1537)
- feat: invalid staleness period prevention [PR #1536](https://github.com/layr-labs/eigenlayer-contracts/pull/1536)