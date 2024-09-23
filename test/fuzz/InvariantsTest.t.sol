// SPDX-License-Identifier: MIT

// Should house our invariants aka properties that should always hold.
/* 
*   - Total supply of DSC should be less than the total value of collateral deposits
*   - Getter view functions should never revert <-- evergreen invariant
^ are the focus for now
*   - Users cannot redeem more than they deposit
*   - Positions can be liquidated when health factor is below 1
*   - Positions cannot be liquidated when HF is 1 or above
*
*/

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Handler} from "./Handler.t.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

contract InvariantsTest is StdInvariant,Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address weth;
    address wbtc;
    Handler handler;
    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (,,weth,wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // Get all the value of the collateral in the protocol
        // compare it to all the debt
        uint256 totalWethCollateralDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcCollateralDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
        uint256 totalWethValue = dscEngine.getUsdValue(address(weth), totalWethCollateralDeposited);
        uint256 totalWbtcValue = dscEngine.getUsdValue(address(wbtc), totalWbtcCollateralDeposited);
        console.log("wethValue: %s", totalWethValue);
        console.log("wbtcValue: %s", totalWbtcValue);

        uint256 totalDscSupply = dsc.totalSupply();
        console.log("Total supply: %s", totalDscSupply);
        console.log("Times mintDsc is called: %s", handler.timesMintDscIsCalled());

        assert(totalWethValue + totalWbtcValue >= totalDscSupply);
    }
    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getCollateralTokens();
        dscEngine.getLiquidationBonusMultiple();
        dscEngine.getLiquidationThreshold();
        dscEngine.getTotalDscMinted();
        dscEngine.getMinHealthFactor();
        dscEngine.getDsc();
    }
}