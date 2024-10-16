// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ArbSepoliaConfig {
    // ---------------- PROTOCOL ADDRESSES ----------------
    address constant V1_FACTORY = 0xa2dBe262D27647243Ac3187d05DBF6c3C6ECC14D;
    address constant FEED_FACTORY = 0x21a84b9a5b746Fe85e13f11E745960DBEdB247B1;
    address constant OVL = 0x0000000000000000000000000000000000000000;

    // ---------------- TOKEN CONFIG ----------------
    address constant GOV = 0x95f972fc4D17a0D343Cd5eaD8d6DCBef5606CA66;

    // ---------------- V1 FACTORY CONFIG ----------------
    address constant FEE_RECIPIENT = 0xDFafdfF09C1d63257892A8d2F56483588B99315A;
    // Ref: https://docs.chain.link/data-feeds/l2-sequencer-feeds#available-networks
    address constant SEQUENCER_ORACLE = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    uint256 constant GRACE_PERIOD = 1 hours;

    // ---------------- FEED FACTORY CONFIG ----------------
    uint256 constant MICRO_WINDOW = 600;
    uint256 constant MACRO_WINDOW = 3600;
}
