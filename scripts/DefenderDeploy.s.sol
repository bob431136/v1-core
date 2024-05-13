// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {OverlayV1Token} from "contracts/OverlayV1Token.sol";
import {MINTER_ROLE, GOVERNOR_ROLE} from "contracts/interfaces/IOverlayV1Token.sol";
import {OverlayV1Factory} from "contracts/OverlayV1Factory.sol";
import {Defender} from "scripts/defender/Defender.sol";
import {DefenderOptions} from "scripts/defender/Options.sol";

// 1. Set required environment variables: RPC, DEFENDER_KEY, DEFENDER_SECRET, FOUNDRY_OUT.
// 2. Deploy with:
// $ source .env
// $ forge script scripts/DefenderDeploy.s.sol:DeployScript --rpc-url $RPC --force -vvvv

// Defender reference:
// - https://docs.openzeppelin.com/defender/v2/module/deploy
// - https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades/blob/main/DEFENDER.md

contract DeployScript is Script {
    bytes32 constant ADMIN_ROLE = 0x00;

    // TODO: update values as needed
    address constant GOV = 0x95f972fc4D17a0D343Cd5eaD8d6DCBef5606CA66;
    address constant FEE_RECIPIENT = 0xDFafdfF09C1d63257892A8d2F56483588B99315A;
    // Ref: https://docs.chain.link/data-feeds/l2-sequencer-feeds#available-networks
    address constant SEQUENCER_ORACLE = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    uint256 constant GRACE_PERIOD = 1 hours;

    function run() public {
        // NOTE: a salt is needed when using a Safe multisig to deploy
        DefenderOptions memory opts;
        opts.salt = "123"; // random value

        address deployed = Defender.deployContract("OverlayV1Token.sol", opts);
        console2.log("Deployed contract to address", deployed);
    }

    // function run() external {
    //     uint256 DEPLOYER_PK = vm.envUint("DEPLOYER_PK");
    //     address deployer = vm.addr(DEPLOYER_PK);

    //     vm.startBroadcast(DEPLOYER_PK);

    //     // <!---- START DEPLOYMENT ---->
        
    //     // 1. Deploy token contract
    //     OverlayV1Token ovl = new OverlayV1Token();

    //     // 2. Deploy factory contract
    //     OverlayV1Factory factory = new OverlayV1Factory(
    //         address(ovl),
    //         FEE_RECIPIENT,
    //         SEQUENCER_ORACLE,
    //         GRACE_PERIOD
    //     );

    //     // 3. Grant factory admin role so that it can grant minter + burner roles to markets
    //     ovl.grantRole(ADMIN_ROLE, address(factory));

    //     // 4. Grant admin rights to governance
    //     ovl.grantRole(ADMIN_ROLE, GOV);
    //     ovl.grantRole(MINTER_ROLE, GOV);
    //     ovl.grantRole(GOVERNOR_ROLE, GOV);

    //     // 5. Renounce admin role so only governance has it
    //     ovl.renounceRole(ADMIN_ROLE, deployer);

    //     // <!-- END DEPLOYMENT -->

    //     vm.stopBroadcast();

    //     console2.log("Token deployed at:", address(ovl));
    //     console2.log("Factory deployed at:", address(factory));
    // }
}
