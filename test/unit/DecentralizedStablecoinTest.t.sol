// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract DecentralizedStablecoinTest is StdCheats, Test {
    DecentralizedStableCoin dsc;
    address public OWNER = makeAddr("owner");
    uint256 public constant DSC_AMOUNT = 10 ether;

    function setUp() public {
        vm.startPrank(msg.sender);
        dsc = new DecentralizedStableCoin();
        dsc.transferOwnership(OWNER);
        vm.stopPrank();
    }
    // Things to test
    // Mint must be more than zero DecentralizedStableCoin__MustBeMoreThanZero();
    // Mint can't go to the zero address DecentralizedStableCoin__NotZeroAddress();

    ////////////////
    // Mint Tests //
    ////////////////
    function testRevertIfZeroMinted() public {
        vm.prank(OWNER);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        bool success = dsc.mint(OWNER,0);
        assert(!success);
    }

    function testRevertIfGoingToZeroAddress() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        vm.prank(OWNER);
        dsc.mint(address(0), DSC_AMOUNT);
    }

    function testOnlyOwnerCanMint() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector,msg.sender));
        vm.prank(msg.sender);
        dsc.mint(OWNER, DSC_AMOUNT);
    }

    function testOwnerCanMint() public {
        vm.prank(OWNER);
        bool success = dsc.mint(OWNER,DSC_AMOUNT);
        assert(success);
        assertEq(dsc.balanceOf(OWNER),DSC_AMOUNT);
    }

    ////////////////
    // Burn Tests //
    ////////////////
    // Burn must be more than zero DecentralizedStableCoin__MustBeMoreThanZero();
    // Burn can't be more than user's balance  DecentralizedStableCoin__MustNotExceedBalance();
    // BurnFrom can't be used DecentralizedStableCoin__BlockFunction();
    modifier DscMinted {
        vm.prank(OWNER);
        dsc.mint(OWNER, DSC_AMOUNT);
        _;
    }
    function testRevertIfZeroBurned() public DscMinted{
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        vm.prank(OWNER);
        dsc.burn(0);
    }

    function testRevertIfMoreBurnedThanUserBalance() public DscMinted {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustNotExceedBalance.selector);
        vm.prank(OWNER);
        dsc.burn(DSC_AMOUNT + 5 ether);
    }

    function testOwnerCanBurn() public DscMinted {
        vm.prank(OWNER);
        dsc.burn(DSC_AMOUNT);
        assertEq(dsc.balanceOf(OWNER), 0);
    }

    ///////////////////
    // BurnFrom Test //
    ///////////////////

    function testRevertIfBurnFromCalled() public DscMinted {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BlockFunction.selector);
        vm.prank(OWNER);
        dsc.burnFrom(OWNER, DSC_AMOUNT);
    }
}