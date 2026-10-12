// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {ComplianceRegistry} from "../../src/ComplianceRegistry.sol";
import {TBillToken} from "../../src/TBillToken.sol";
import {TBillVault} from "../../src/TBillVault.sol";
import {MockPriceFeed} from "../../src/exercises/MockPriceFeed.sol";
import {MockTBillCustodian} from "../../src/exercises/MockTBillCustodian.sol";

/// @title Ex2 + Ex3 + Ex4 — three planks of the bridge: custody (a), attestation (b), admission (d)
/// @notice The bridge is how an off-chain asset becomes an on-chain token. Each exercise below
///         pulls on one plank and shows you what is holding the span up — and what is not.
///         The fourth plank, redemption (c), is the queue you write in Ex5.
///
///         Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/TBill.t.sol — it contains the answers. Write yours first, and
///         only look once you are stuck.
contract BridgeTasksTest is Test {
    MockUSDC internal usdc;
    ComplianceRegistry internal compliance;
    MockPriceFeed internal feed;
    TBillToken internal tBill;
    MockTBillCustodian internal custodian;
    TBillVault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant PAR = 1e8;
    uint256 internal constant NAV_1_25 = 1.25e8;

    function setUp() public {
        usdc = new MockUSDC();
        compliance = new ComplianceRegistry(admin);
        feed = new MockPriceFeed(int256(PAR));
        tBill = new TBillToken(admin, compliance);
        custodian = new MockTBillCustodian(admin);
        vault = new TBillVault(usdc, tBill, feed, custodian, admin);

        tBill.grantRole(tBill.MINTER_ROLE(), address(vault));
        custodian.grantRole(custodian.CUSTODIAN_ROLE(), address(vault));

        compliance.setWhitelisted(admin, true);
        compliance.setWhitelisted(alice, true);
        compliance.setWhitelisted(bob, true);
    }

    /// @dev Given: pay `assets` of USDC and receive shares at today's NAV
    function _subscribe(address user, uint256 assets) internal {
        usdc.faucet(user, assets);
        vm.startPrank(user);
        usdc.approve(address(vault), assets);
        vault.subscribe(assets);
        vm.stopPrank();
    }

    // ==================================================================
    // Ex2 · plank (a) custody — the shares exist, the box may not
    // ==================================================================

    /// @dev Subscribe 1000 USDC at par, then look at both sides of the bridge at once: the
    ///      shares alice now holds, and what the custodian actually holds.
    ///      Hint: _subscribe(alice, 1_000e6), then compare tBill.balanceOf(alice) with
    ///      custodian.realHoldings(). One of them is 1000e18; the other is zero. Assert both,
    ///      then ask yourself which contract ever talked to the custodian.
    function test_Ex2_SharesExistWhileTheCustodianHoldsNothing() public {
    // 1. Alice subscribes with 1000e6 (1000 USDC)
    _subscribe(alice, 1_000e6);

    // 2. Assert: Check if Alice's account has 1000e18 tokens, 1000e6 USDC * 1e20 / 1e8(NAV) = 1000e18 shares
    assertEq(tBill.balanceOf(alice), 1000e18);

    // 3. Assert: Check whether the custodian's ledger is 0
    // subscribe function doesn't communicate with the custodian at all, the USDCmoney just sits in the vault
    assertEq(custodian.realHoldings(), 0);
}

    /// @dev The custodian's `treasury` is a number a permissioned address can move. Prove that
    ///      the "backing" is a typed-in integer, not cash that arrived.
    ///      Hint: recordPurchase is onlyRole(CUSTODIAN_ROLE) and `admin` holds it. Call
    ///      custodian.recordPurchase(1_000_000e6), then assert realHoldings() jumped while
    ///      usdc.balanceOf(address(custodian)) is still zero.
    function test_Ex2_RealHoldingsIsJustANumber() public {
    // 1. Act as admin (because admin has been granted the CUSTODIAN_ROLE in setUp)
    vm.prank(admin);

    // 2. Call recordPurchase to forcefully change the custodian's ledger to 1 million USDC
    custodian.recordPurchase(1_000_000e6);

    // 3. Assert: The amount on the custodian's ledger has indeed become 1 million
    assertEq(custodian.realHoldings(), 1_000_000e6);

    // 4. Assert: the actual USDC balance in the custodian contract remains 0!
    assertEq(usdc.balanceOf(address(custodian)), 0);
}

    // ==================================================================
    // Ex3 · plank (b) attestation — the chain's only window is one number
    // ==================================================================

    /// @dev Subscribe at par, then have the reporter move the NAV up. Assert the two things
    ///      that make this an RWA and not a stablecoin: the share COUNT is unchanged, and the
    ///      VALUE of the position moved. A stablecoin would have kept things 1:1.
    ///      Hint: _subscribe(alice, 1_000e6); read tBill.balanceOf(alice) and
    ///      vault.totalClaimValue(); then vault.attest(int256(NAV_1_25)); read both again.
    ///      Shares stay 1000e18; the claim goes 1000e6 -> 1250e6.
    function test_Ex3_TheClaimFloats_TheShareCountDoesNot() public {
    // 1. Alice purchase 1000 USDC at NAV=1.00 and obtain 1000e18 shares
    _subscribe(alice, 1_000e6);

    // 2. Record the current total number of shares and the total book value
    uint256 sharesBefore = tBill.totalSupply();
    uint256 claimBefore = vault.totalClaimValue();

    // 3. Acting the role of admin (with the REPORTER_ROLE), call attest to change the NAV from 1e8 to 1.25e8
    vm.prank(admin);
    vault.attest(1.25e8);

    // 4. Reread the share and book value
    uint256 sharesAfter = tBill.totalSupply();
    uint256 claimAfter = vault.totalClaimValue();

    // 5. Assert: The share remains unchanged
    assertEq(sharesAfter, sharesBefore);
    assertEq(sharesAfter, 1000e18);

    // 6. Assert: The book value has increased from 1000e6 to 1250e6
    assertEq(claimBefore, 1000e6);
    assertEq(claimAfter, 1250e6); 
}

    /// @dev One number re-prices the entire book. Two holders, one call, and both claim values
    ///      move together. attest is gated by REPORTER_ROLE — `admin` holds it — but nothing
    ///      downstream can question the number it writes.
    ///      Hint: _subscribe alice and bob, then vault.attest. A single holder's claim value is
    ///      vault.assetsForShares(tBill.balanceOf(who)). Pick a moderate NAV (e.g. 50e8) so the
    ///      totals stay small and readable.
    function test_Ex3_OneCallMovesTheWholeBook() public {
    // 1. Alice and Bob each subscribed for 1000 USDC and each received 1000e18 shares
    _subscribe(alice, 1_000e6);
    _subscribe(bob, 1_000e6);

    // 2. Verify that when NAV=1.00, the book value of 1000e18 shares held by each person is 1000e6
    assertEq(vault.assetsForShares(1_000e18), 1_000e6);

    // 3. REPORTER_ROLE adjusted the NAV to 1.25e8 (1.25)
    vm.prank(admin);
    vault.attest(1.25e8);

    // 4. The book value of both Alice and Bob simultaneously changed to 1250e6
    assertEq(vault.assetsForShares(1_000e18), 1_250e6);
}

    // ==================================================================
    // Ex4 · plank (d) admission — where the guard is, and who holds the key
    // ==================================================================

    /// @dev An address that never passed KYC cannot receive shares, even by paying for them.
    ///      Hint: faucet the attacker and approve the vault FIRST, or you revert for the wrong
    ///      reason. Then vm.expectRevert + abi.encodeWithSelector to pin down
    ///      TBillToken.NotWhitelisted(attacker). A vague "it reverted" stays green even after
    ///      the guard is removed, so assert the exact selector.
    function test_Ex4_NoKyc_NoShares_EvenIfYouPay() public {
    // 1. Send test coins to the attacker and authorize them to the vault 
    usdc.faucet(attacker, 1_000e6);
    vm.prank(attacker);
    usdc.approve(address(vault), 1_000e6);

    // 2. Expected error message: The contract will revert due to "not being on the whitelist"
    vm.expectRevert(abi.encodeWithSelector(TBillToken.NotWhitelisted.selector, attacker));

    // 3. The attacker attempts to make a purchase application
    vm.prank(attacker);
    vault.subscribe(1_000e6);
}

    /// @dev A whitelisted holder still cannot SEND shares to a non-whitelisted address —
    ///      _update checks both endpoints, not just the sender.
    ///      Hint: alice subscribes, then alice calls tBill.transfer(attacker, 1e18). Pin the
    ///      revert on NotWhitelisted(attacker) — note WHICH address appears in the error.
    function test_Ex4_TransferChecksBothEndpoints() public {
    // 1. Alice make a normal subscription and obtain 1000e18 shares
    _subscribe(alice, 1_000e6);

    // 2. Expected error: The receiver (attacker) is not on the whitelist
    vm.expectRevert(abi.encodeWithSelector(TBillToken.NotWhitelisted.selector, attacker));

    // 3. Alice attempts to transfer 1 share to the attacker
    vm.prank(alice);
    tBill.transfer(attacker, 1e18);
}

    /// @dev Removing an address from the list freezes that individual holder — and it is
    ///      stronger than it looks. The same _update guard sits in front of burn(), so once
    ///      alice is off the list the issuer cannot confiscate her shares either.
    ///      Hint: alice subscribes; compliance.setWhitelisted(alice, false); assert alice's
    ///      transfer reverts; then assert tBill.burn(alice, 1_000e18) called by admin ALSO
    ///      reverts NotWhitelisted(alice). Do not reach for pause() — that is a global switch,
    ///      a different question (STUDENT-QUESTIONS.md C2).
    function test_Ex4_FreezeBeatsConfiscation() public {
    // 1. Alice make a normal subscription and obtain 1000e18 shares
    _subscribe(alice, 1_000e6);

    // 2. The admin removed Alice from the whitelist (freezing her)
    vm.prank(admin);
    compliance.setWhitelisted(alice, false);

    // 3. Assert 1: Now, Alice can't even transfer 1 share to others.
    // This time, the error message indicates that the input is "alice", because the error originates from checking the "from" field (sender)
    vm.expectRevert(abi.encodeWithSelector(TBillToken.NotWhitelisted.selector, alice));
    vm.prank(alice);
    tBill.transfer(bob, 1e18); 

    // 4. Assert 2: The admin cannot forcibly burn her shares (burning also goes through the from check of _update)
    vm.expectRevert(abi.encodeWithSelector(TBillToken.NotWhitelisted.selector, alice));
    vm.prank(admin);
    tBill.burn(alice, 1_000e18);
}
}
