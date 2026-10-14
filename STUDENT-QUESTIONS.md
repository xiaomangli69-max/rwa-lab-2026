# STUDENT-QUESTIONS.md — Discussion questions (goes inside your submission zip)

Answer directly under each question. 150–300 words each — **reasoning over length**.

The sections follow the four planks of the bridge. There are no standard answers; these are the
real point of the lab.

---

## A. Custody — where the asset actually is (plank a)

**A1.** In Lab 1, `totalCollateral()` read the vault's own ERC-20 balance, and the chain could
prove the invariant. Here, `MockTBillCustodian.realHoldings()` is just a number that a permissioned
address can move. Write the equivalent of `totalCollateral() == totalSupply()` for *this* system.
What does it actually assert, and what does it no longer prove?

> Your answer:
>
>The invariant for this RWA system would be：MockTBillCustodian.realHoldings() == TBillToken.totalSupply()
>
>Actually assert：The total amount of tokens issued on the chain should be consistent with the book value of offline treasury bonds reported in the contract by the custodian account, ensuring no mismatch in internal bookkeeping.This is essentially an "oracle statement" or "trust assumption", which assumes that the centralized custodian reports the assets it holds honestly and accurately.
>
>No longer prove：However, compared to Lab1's pure on-chain stablecoin, this equation can no longer cryptographically prove the existence of the underlying real-world assets. In Lab1, `totalCollateral()` reads the real ERC20 balance of the treasury contract, and the data is automatically maintained by the blockchain, which cannot be unilaterally tampered with. While `realHoldings()` is just a number manually maintained by the administrator within the custodian contract, which can be modified at will by privileged accounts. Even if the equation remains equal, the custodian may sell, pledge, or lose the treasury bond in reality. The smart contract can only verify the ledger, but cannot verify in the real world whether the treasury bond is truly and intactly custodied.


<br><br><br>

**A2.** The T-Bills are held by an SPV, a legal entity set up so the fund's assets are bankruptcy-
remote from the issuer. Explain in your own words why a *legal* structure is part of a *technical*
design. If the SPV's custodian goes bankrupt, what does the on-chain token entitle its holder to?

> Your answer:
>
>1. Smart contracts can only execute on-chain code and cannot manage real-world financial assets and legal rights. Therefore, legal structures such as SPV are an indispensable part of the RWA token technology design. As an independent legal entity, SPV holds short-term treasury bonds to achieve bankruptcy remoteness: even if the token issuing entity goes bankrupt, the treasury bond assets under the SPV will not be pursued by the creditors of the issuer, thus protecting the underlying assets corresponding to the token holders.
>
>2. The on-chain TBill token is not the treasury bond itself; it represents the holder's proportional legal claim to the underlying assets of the SPV.If the custodian institution corresponding to the SPV goes bankrupt, the smart contract cannot automatically dispose of and transfer real-world treasury bonds. Token holders cannot retrieve the bonds directly through the contract, but can only rely on the on-chain tokens as proof of ownership, go through offline bankruptcy legal procedures, and apply for asset distribution from the SPV liquidation. Whether and how much they can retrieve ultimately depends on the court's liquidation results, as blockchain cannot enforce the delivery of real assets.

<br><br><br>

---

## B. Attestation — how the chain learns the truth (plank b)

**B1.** `attest()` is the only function that moves the NAV, and it is gated by `REPORTER_ROLE`.
Everything downstream — subscription pricing, redemption payouts, both invariants — believes that
number. Name the failure modes of a single trusted reporter, and one mechanism (technical,
financial, or legal) that mitigates each.

> Your answer:
> 
> 1. Malicious misreporting: The reporter deliberately submits a false NAV. For example, when the price of treasury bonds falls, they report an inflated net value and sell the tokens at a high price, harming the interests of buyers. 
>
>    Mitigation solution (technical): Introduce multi-signature/multiple oracles, requiring multiple independent reporting entities to jointly vote and confirm the NAV, and disallowing single-person modification of the net value.
> 
> 2. Private key leakage and data tampering by external attackers：After stealing the private key of the REPORTER_ROLE account, hackers can arbitrarily call the attest function to tamper with NAV. 
>
>    Mitigation solution (technical): Use a multi-signature wallet to store the reporter's private key, and require multiple key signatures to modify NAV.
> 
> 3. The reporter is offline and unreachable, the NAV is not updated for a long time, the net value is frozen, and the system cannot perform normal pricing. 
>
>     Mitigation solution (legal): Pre-agree on a backup reporter. When the primary reporter is unable to submit data for an extended period, the backup reporter will take over the reporting authority.

<br><br><br>

**B2.** A production feed would check whether `updatedAt` is stale; this lab's mock does not. A
**frozen** NAV is a different attack from a **wrong** NAV. Describe how a stale-but-honest NAV can
be exploited by someone who knows the true value has moved.

> Your answer:
>
>The stale-but-honest NAV refers to the situation where the NAV value reported last time was true and accurate, but in reality, the underlying treasury bond prices have changed, and the on-chain data has not been updated, remaining in a frozen state. This is different from attacks that actively falsify false net values. 
>
>Assuming that the real market price of the treasury bond has fallen, but the on-chain NAV still maintains the previous higher old net value. The attacker, who has access to the real market conditions, can buy TBill tokens before the on-chain price is updated and then initiate a redemption based on the outdated high NAV in the contract. The contract will pay out funds according to the old high price, and the payout amount will be higher than the true value of the underlying asset, allowing the attacker to earn the difference and continuously consume the system's collateral assets. 
>
>Conversely, if the real market price of the treasury bond rises and the on-chain NAV remains at a lower old value, the attacker can purchase tokens at a low price and wait for the NAV to update and rise before redeeming for profit. This attack exploits the price time difference between the on-chain and off-chain markets to complete arbitrage before the oracle refreshes.

<br><br><br>

---

## C. Redemption — T+1 does not settle on-chain (plank c)

**C1.** The queue locks the payout at the NAV of **enqueue** time, not **settle** time. If the NAV
rises between the two, who gains and who loses — the redeemer, or the holders who stayed? Is that
the right allocation of risk, and how would you change it?

> Your answer:
> 
>The redemption queue locks the NAV at the time the user submits the redemption application (enqueue), rather than at the final settlement moment. If the NAV rises during the waiting period for settlement, the redemption applicant can only settle using the lower NAV at the time of application and will not be able to obtain the gains from the rise; all gains will be obtained by the remaining holders who continue to hold the tokens.
>
>This risk allocation is unreasonable, as it involves asymmetric risks: if the NAV declines, as long as users preemptively submit redemption requests, they can secure a safe exit with a higher NAV, while the losses from asset decline are borne entirely by the remaining holders. This will incentivize everyone to rush to submit redemption requests during market panic, amplifying the risk of a run on the bank.
>
>Improvement approach: Implement a floating or pro-rata loss allocation mechanism for the redemption queue; adjust the payment price to the NAV at the time of settlement. Redemption applications will only be queued, and the final settlement price will be based on the net value at the moment of fund payment. Redemption applicants will also bear the risk of NAV fluctuations during the waiting period, eliminating the incentive to queue up early for risk aversion and balancing risks.

<br><br><br>

**C2.** In a 2008 money-market fund breaking the buck, and in USDC's 2023 depeg, redemptions were
handled very differently. Compare the two. For a tokenized T-Bill fund, what does it mean to "close
the redemption channel", and what should happen to the queue when it does? Then look at the lever
this lab actually ships: `pause()` (`PAUSER_ROLE`) freezes transfers, minting **and** redemption
together — one switch, no partial setting. Why is that the wrong tool for a liquidity squeeze, and
what would you rather have?

> Your answer:
> 
> In the 2008 event where money funds fell below par value, the redemption channel was not completely closed; instead, the rigid one-dollar principal guarantee was merely cancelled, and redemptions were settled at the true asset discount, with users bearing losses upon redemption. In contrast, the 2023 USDC de-pegging event directly suspended redemption payments, preventing depositors from withdrawing reserve assets, pending the resolution of underlying asset risks. The key difference between the two lies in: the former retains the redemption channel but gives up the principal guarantee, while the latter directly closes the payment channel.
> 
> For tokenized US Treasury bond funds, closing the redemption channel means no longer accepting new redemption applications. When the channel is closed, orders that have already entered the redemption queue should continue to be settled according to the original rules, and cannot be directly voided from the queue.
> 
> The `pause()` function in this experiment serves as a global master switch, freezing all functions of transfer, minting, and redemption at once, with no individual control over any of them. In a liquidity run scenario, this tool is not suitable: during a crisis, it is only necessary to block new redemptions to protect the asset pool, without freezing token transfers, nor should it prohibit new users from purchasing to replenish funds. A blanket freeze of all functions would completely destroy market confidence and exacerbate panic. A better solution is to set independent control switches for minting, redemption, and transfer; in the event of a run, only suspend new redemptions, retain token transfer and subscription functions, and settle submitted redemptions in the queue normally. At the same time, risk control measures such as redemption limits and tiered discounted redemptions can be employed.

<br><br><br>

---

## D. Admission — the guest list and the backdoor (plank d)

**D1.** Every balance change in `TBillToken._update` checks **both** endpoints against the
whitelist. That is what stops a sanctioned address from receiving shares — and also what stops a
completely ordinary user who has not finished KYC. Where is the right line for a regulated fund,
and who should be able to move it?

> Your answer:
> 
> 1. `TBillToken._update` verifies the whitelist status of both the sending and receiving addresses simultaneously during balance changes. This mechanism can intercept tokens received by sanctioned addresses or ordinary users who have not completed KYC. However, verifying both ends simultaneously can bring additional side effects: once a compliant holder is removed from the whitelist, he will also be unable to transfer tokens to other compliant whitelist addresses.
> 
>    For regulated tokenized treasury bond funds, the core regulatory objective is to prevent non-compliant, sanctioned, and non-KYC entities from holding fund shares, that is, to ensure that tokens can only be held by compliant addresses in the end, rather than restricting compliant holders from transferring out assets.
> 
> 2. The reasonable boundary should be: Only the recipient's address must be verified to be in the whitelist, and there is no need to simultaneously verify the sender's address. 
> 
>    This scheme can still prevent tokens from being received by non-KYC addresses (if the recipient is not on the whitelist, the transaction will be rolled back directly), but retains one capability: if an address is removed from the whitelist, the tokens in the account can still be transferred to other compliant whitelisted users, facilitating asset disposal.
> 
> 3. The entities that can transfer tokens include: token holders who have completed KYC procedures, passed the access review, and been added to the whitelist
> 
>    The current strategy of simultaneous verification at both ends is overly strict, which can lead to assets being directly locked once the address is removed from the whitelist, making it impossible to transfer to a compliant address.

<br><br><br>

**D2.** A regulated fund asks for two levers: freeze an address (`setWhitelisted(addr, false)`) and
burn a balance (`MINTER_ROLE`) — both censorship tools, both justified by the product. But Ex4.3
shows the two **collide**: once an address is off the list, `burn()` reverts as well, because
`_update` guards both endpoints. So a freeze also blocks a seizure. Argue **both** sides of handing
an issuer these powers, then say what safeguards you would add and who should hold each key.

> Your answer:
> 
> Proponent's view: The token is a regulated fund share. In scenarios involving anti-money laundering and international sanctions, the issuer needs to possess the ability to freeze suspicious addresses and legally seize and destroy account assets, in order to intercept criminal funds and fulfill regulatory compliance obligations. 
> 
> Opponent's view: These two tools constitute powerful censorship powers and are akin to backdoors for assets. If solely controlled by the issuer, there is a risk of abuse, where ordinary users' tokens can be arbitrarily frozen or even confiscated, undermining the ownership protection of user assets.
> 
> Currently, there is a functional conflict: after an address is removed from the whitelist and frozen, the whitelist verification of the regular `_update` will prevent the execution of burn destruction on that address, making it impossible to complete asset seizure. Additional protection mechanisms are needed:
> 
> 1. Separation of permissions, ensuring that no single account can hold all permissions; the use of multi-party multi-signature mechanisms for whitelist freezing and asset destruction.
> 
> 2. Judicial preposition: The execution of burn asset seizure must be accompanied by official documents from regulators or courts, with all operations fully documented on the blockchain for public auditing.
> 
> 3. Special handling at the code level: Implementing destruction operations for judicial confiscation, exempting from white list verification logic for regular transfers, and resolving conflicts arising from the inability to seize assets after they have been frozen.
> 
> 4. Introduce a user complaint mechanism, allowing users to submit proof and apply for restoration to the whitelist for addresses that have been mistakenly frozen.
> 
> Authority Custody: The management authority of the whitelist is entrusted to an independent, compliant multi-party committee; the key for asset destruction and seizure is jointly safeguarded by multiple parties.

<br><br><br>

---

## E. Tests (Tier 1 required — this is Ex2, Ex3 and Ex4)

Turn the red tests green in `test/exercises/01_BridgeTasks.t.sol` to cover the scenarios below, and
write your test function names here:

| Plank | Scenario | Your test function name |
|---|---|---|
| a | Shares exist while the custodian holds nothing | test_Ex2_SharesExistWhileTheCustodianHoldsNothing() |
| a | `realHoldings()` moves with no cash moving | test_Ex2_RealHoldingsIsJustANumber() |
| b | The claim value floats while the share count stays | test_Ex3_TheClaimFloats_TheShareCountDoesNot() |
| b | One `attest` re-prices every holder at once | test_Ex3_OneCallMovesTheWholeBook() |
| d | A non-whitelisted address cannot receive shares, even by paying | test_Ex4_NoKyc_NoShares_EvenIfYouPay() |
| d | A whitelisted holder cannot send shares to a non-whitelisted address | test_Ex4_TransferChecksBothEndpoints() |
| d | Removing an address freezes that holder — and blocks a burn | test_Ex4_FreezeBeatsConfiscation() |

Then write one more scenario you consider **most likely to be exploited** on a tokenized fund, and
say which plank it breaks:

> Your answer:
>
>The most vulnerable point of the tokenized US Treasury bond fund is the privileged NAV manipulation through the `attest` function, which undermines Pillar b (the attestation valuation mechanism). 
>
>`attest` is controlled exclusively by administrators with the REPORTER_ROLE, lacking time locks, price range verification, and independent cross-validation of external US Treasury bond market prices. An infiltrated or malicious reporter can arbitrarily modify the NAV. Before the actual US Treasury bond price drops, the reporter maintains an artificially high net value, allowing insiders to submit redemptions at high prices, draining the USDC reserves in the treasury; before the bond price is about to rise, the attacker subscribes at a low price, and profits after the net value is corrected. This attack exploits the weakness that the asset value of all users is completely recalculated based on a single manually reported value, creating unfair subscription and redemption arbitrage, draining fund reserves, and destroying trust between off-chain custodial assets and on-chain tokens.
