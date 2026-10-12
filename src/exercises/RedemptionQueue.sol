// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {TBillToken} from "../TBillToken.sol";
import {TBillVault} from "../TBillVault.sol";

/// @title The redemption queue (Ex5) — four TODOs are waiting for you
/// @notice This is plank (c) of the bridge, the physical side. Selling a T-Bill and wiring the
///         cash takes a day (T+1 as it settles), so a redemption cannot be atomic. Instead the
///         holder hands in their shares and gets a ticket; when the issuer's cash lands, the
///         tickets are honoured strictly first-in-first-out. When cash is short, the queue
///         backs up — and the people at the back are the ones who wait.
///
///         This is also where the decimals bite again. Three scales:
///           shares    18 decimals  (tBILL)
///           NAV        8 decimals  (per share)
///           assets     6 decimals  (USDC)
contract RedemptionQueue is AccessControl {
    using SafeERC20 for IERC20;

    TBillVault public immutable vault;
    TBillToken public immutable tBill;
    IERC20 public immutable usdc;

    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");

    uint256 public constant NAV_PRECISION = 1e8;
    uint256 public constant SHARE_PRECISION = 1e18;
    uint256 public constant ASSET_PRECISION = 1e6;
    /// @dev 18 + 8 - 6 — the same number as in the vault
    uint256 public constant DECIMALS_SCALE = 1e20;

    struct Request {
        address owner;
        uint256 shares; // escrowed shares, 18 decimals
        uint256 assetsLocked; // payout promised at the NAV when enqueued, 6 decimals
        bool settled;
    }

    Request[] public requests;

    /// @dev Index of the first request that has not been settled — the head of the queue
    uint256 public head;
    /// @dev Shares held by this contract, backing the unsettled requests
    uint256 public pendingShares;
    /// @dev Assets still owed to the unsettled requests, 6 decimals
    uint256 public pendingAssets;
    /// @dev Cash settled and waiting to be claimed
    uint256 public totalClaimable;
    mapping(address => uint256) public claimable;

    event RedeemRequested(
        uint256 indexed id, address indexed owner, uint256 shares, uint256 assetsLocked
    );
    event Settled(uint256 indexed id, address indexed owner, uint256 assets);
    event Claimed(address indexed owner, uint256 assets);

    error ZeroAddress();
    error ZeroAmount();
    error NothingToClaim();

    constructor(TBillVault vault_, TBillToken tBill_, IERC20 usdc_, address admin) {
        if (
            address(vault_) == address(0) || address(tBill_) == address(0)
                || address(usdc_) == address(0) || admin == address(0)
        ) revert ZeroAddress();
        vault = vault_;
        tBill = tBill_;
        usdc = usdc_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SETTLER_ROLE, admin);
    }

    // ==================================================================
    // Given to you — read-only helpers, do not touch
    // ==================================================================

    function queueLength() external view returns (uint256) {
        return requests.length;
    }

    function requestAt(uint256 id) external view returns (Request memory) {
        return requests[id];
    }

    // ==================================================================
    // TODO Ex5.1 — the decimal conversion
    // ==================================================================

    /// @notice Value `shares` (18 decimals) in USDC smallest units (6 decimals), at an
    ///         8-decimal NAV
    /// @dev The product carries 18 + 8 = 26 decimals and you want 6 — divide by 10 to the what?
    function assetsAtNav(uint256 shares, uint256 nav) public pure returns (uint256) {
    return shares * nav / DECIMALS_SCALE;
}

    // ==================================================================
    // TODO Ex5.2 — take the ticket
    // ==================================================================

    /// @notice Hand in `shares` and lock in a payout at today's NAV
    /// @dev Steps:
    ///        1) reject a zero amount
    ///        2) pull the shares in — the caller must have approved this contract first
    ///        3) read today's NAV and lock the payout with assetsAtNav
    ///        4) record the ticket and return its id
    ///        5) keep pendingShares and pendingAssets in step with what is outstanding
    ///      Locking the rate now is the point: the payout must not drift with the NAV while
    ///      the ticket waits in the queue.
    function enqueue(uint256 shares) external returns (uint256 id) {
    // 1. Refuse zero shares
    if (shares == 0) revert ZeroAmount();

    // 2. Pull the user's share into the queue (the user must first approve the queue)
    IERC20(address(tBill)).safeTransferFrom(msg.sender, address(this), shares);

    // 3. Read today's NAV and lock the payout using assetsAtNav
    uint256 nav = vault.navPerShare();
    uint256 assetsLocked = assetsAtNav(shares, nav);

    // 4. Record the ticket stub and return the id
    id = requests.length;
    requests.push(Request({
        owner: msg.sender,
        shares: shares,
        assetsLocked: assetsLocked,
        settled: false
    }));

    // 5. Keep pendingShares and pendingAssets up to date with the progress of pending settlements
    pendingShares += shares;
    pendingAssets += assetsLocked;

    emit RedeemRequested(id, msg.sender, shares, assetsLocked);
}

    // ==================================================================
    // TODO Ex5.3 — honour the queue, first in first out
    // ==================================================================

    /// @notice `assets` of cash has arrived from selling the underlying; pay out tickets
    ///         strictly from the head, oldest first
    /// @dev A ticket is honoured in full or not at all. If the remaining cash cannot cover
    ///      the next ticket, stop and leave it for the next settlement — never pay a later
    ///      ticket ahead of an earlier one.
    ///      For each ticket you settle:
    ///        - pull exactly that ticket's cash out of the vault
    ///        - mark it settled and advance `head`
    ///        - burn its escrowed shares
    ///        - decrement pendingShares and pendingAssets
    ///        - credit the owner's claimable balance and totalClaimable
    ///      Return how much you actually paid out.
    function settle(uint256 assets) external onlyRole(SETTLER_ROLE) returns (uint256 filled) {
    // As long as there are tickets left in the queue and the cash is sufficient to pay for the ticket at the head of the queue
    while (head < requests.length) {
        Request storage req = requests[head];

        // If the remaining money is not enough to pay for this ticket, break immediately, and never skip it to pay for the next person
        if (assets - filled < req.assetsLocked) {
            break;
        }

        // 1. Withdraw cash from the vault and deposit it into the queue
        vault.releaseReserves(address(this), req.assetsLocked);

        // 2. Marked as settled
        req.settled = true;

        // 3. Destroy the managed stocks (Note: the caller of burn is the queue itself)
        tBill.burn(address(this), req.shares);

        // 4. Update the ledger
        pendingShares -= req.shares;
        pendingAssets -= req.assetsLocked;

        // 5. Record the transaction for the user (the user can now claim)
        claimable[req.owner] += req.assetsLocked;
        totalClaimable += req.assetsLocked;

        // 6. Increase the issued amount, and move forward as a team
        filled += req.assetsLocked;
        
        emit Settled(head, req.owner, req.assetsLocked);
        head++;
    }
    return filled;
}

    // ==================================================================
    // TODO Ex5.4 — collect
    // ==================================================================

    /// @notice Withdraw the cash credited to you by settled tickets
    /// @dev Checks-effects-interactions: zero the balance before the transfer.
    function claim() external returns (uint256 assets) {
    assets = claimable[msg.sender];
    if (assets == 0) revert NothingToClaim();

    // 1. First, reset the account book (Checks-Effects)
    claimable[msg.sender] = 0;
    totalClaimable -= assets;

    // 2. Further transfers (Interactions)
    usdc.safeTransfer(msg.sender, assets);

    emit Claimed(msg.sender, assets);
}
}
