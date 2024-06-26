from ape import chain, accounts, Contract
import ape
import pandas as pd
from ape.utils import ZERO_ADDRESS

DAY = 24 * 60 * 60
WEEK = DAY * 7

df = pd.DataFrame(
    columns=[
        "Scenarios",
        "Admin Fee % YBS",
        "Admin Fee % Treasury",
        "Admin Fee % Leftover",
        "Vote Incentive % YBS",
        "Vote Incentive % Treasury",
        "Vote Incentive % Leftover",
    ]
)

CONTRACT_NAMES = {
    '0x794f80E899c772de9E326eC83cCfD8D94e208B49': '0x Splits',
    '0x2e13f7644014F6E934E314F0371585845de7B986': 'Receiver',
    '0xf4e55515952BdAb2aeB4010f777E802D61eB384f': 'Splitter',
    '0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde': 'Treasury',
    '0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E': 'crvUSD',
    '0xBF319dDC2Edc1Eb6FDf9910E39b37Be221C8805F': 'yvcrvUSD',
    '0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914': 'Curve Fee Distro',
    '0x47C4f7534995a50B5fa13ee49852B212Ea7d23eE': 'yFee Burner',
    '0x0000000000000000000000000000000000000000': 'ZERO_ADDRESS',
    '0xF147b8125d2ef93FB6965Db97D6746952a133934': 'yVoter',
}


def test_splitter(
    dev,
    splitter,
    crvusd_whale,
    ylockers_ms,
    gov,
    crvusd,
    yvcrvusd,
    reward_distributor,
    fee_burner,
    receiver,
    new_fee_distributor,
    top_up_curve_fee_distributor,
    voter,
):
    admin_split = splitter.getSplits().adminFeeSplits
    voteIncentive_split = splitter.getSplits().voteIncentiveSplits

    print("-- Admin Fees --")
    print(f"{admin_split[0] / 1e16:,.2f}% YBS")
    print(f"{admin_split[1] / 1e16:,.2f}% Treasury")
    print(f"{admin_split[2] / 1e16:,.2f} Leftover")
    print("\n-- Vote Incentives --")
    print(f"{voteIncentive_split[0] / 1e16:,.2f}% YBS")
    print(f"{voteIncentive_split[1] / 1e16:,.2f}% Treasury")
    print(f"{voteIncentive_split[2] / 1e16:,.2f}% Leftover")

    amount = 100_000 * 10**18
    crvusd.transfer(fee_burner, amount, sender=crvusd_whale)

    rewards_before = yvcrvusd.balanceOf(receiver)

    before = crvusd.balanceOf(new_fee_distributor)
    top_up_curve_fee_distributor()  # sends crvUSD, checkpoints, advances 1 week
    assert crvusd.balanceOf(new_fee_distributor) > before

    # if mock_proxy.lastTimeCursor() < WEEK + DAY:
    #     chain.pending_timestamp += WEEK + DAY
    #     chain.mine()


    if can_checkpoint(new_fee_distributor, chain.pending_timestamp):
        new_fee_distributor.checkpoint_token(sender=dev)

    tx = splitter.executeSplit(sender=gov)
    gas = tx.gas_used
    ve = Contract('0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2')
    print(f'⛽⛽⛽⛽ 1 Execute Split: {gas:,}')
    transfers = list(tx.decode_logs(crvusd.Transfer))
    splits = list(tx.decode_logs(splitter.VoteIncentiveSplit))
    splits = splits[0] if len(splits) > 0 else None
    if not splits:
        total_vote_incentives = 0
    else:
        total_vote_incentives = splits.ybs + splits.treasury + splits.remainder
        total_vote_incentives /= 10**18
    splits = list(tx.decode_logs(splitter.AdminFeeSplit))
    splits = splits[0] if len(splits) > 0 else None
    if not splits:
        total_admin_fees = 0
    else:
        total_admin_fees = splits.ybs + splits.treasury + splits.remainder
        total_admin_fees /= 10**18
    print(f"Admin Fees {total_admin_fees:,.2f}")
    print(f"Vote Incentives {total_vote_incentives:,.2f}")
    for t in transfers:
        print(
            CONTRACT_NAMES.get(t.contract_address, t.contract_address), 
            CONTRACT_NAMES.get(t.sender, t.sender), 
            CONTRACT_NAMES.get(t.receiver, t.receiver), 
            f"{t.value/10**18:,.2f}"
        )

    total_rewards = yvcrvusd.balanceOf(receiver)

    tx = receiver.depositRewards(sender=dev)
    fee = receiver.performanceFee() / 10_000 * total_rewards
    deposited = list(tx.decode_logs(reward_distributor.RewardDeposited))[0].rewardAmount
    assert abs(int(total_rewards) - int(fee) - deposited) < 10**18

    assert crvusd.balanceOf(splitter) < 10  # Some dust may exist
    assert yvcrvusd.balanceOf(splitter) < 10  # Some dust may exist

    # Manual Admin fee Split
    # Give CRVUSD to ylockers and perform a deposit and split
    crvusd.transfer(fee_burner, amount, sender=crvusd_whale)
    crvusd.transfer(ylockers_ms, amount, sender=crvusd_whale)
    crvusd.approve(splitter, 2**256 - 1, sender=ylockers_ms)
    tx = splitter.depositAdminFeesAndSplit(amount, sender=ylockers_ms)
    gas = tx.gas_used
    print(f'⛽⛽⛽⛽ 2 depositAdminFeesAndSplit: {gas:,}')
    assert yvcrvusd.balanceOf(receiver) > amount / 2
    assert yvcrvusd.balanceOf(splitter) < 10  # Some dust may exist

    transfers = list(tx.decode_logs(crvusd.Transfer))
    for t in transfers:
        print(
            CONTRACT_NAMES.get(t.contract_address, t.contract_address), 
            CONTRACT_NAMES.get(t.sender, t.sender), 
            CONTRACT_NAMES.get(t.receiver, t.receiver), 
            f"{t.value/10**18:,.2f}"
        )
    
    crvusd.transfer(voter, amount, sender=crvusd_whale)
    tx = splitter.executeSplit(sender=gov)
    gas = tx.gas_used
    print(f'⛽⛽⛽⛽ 3 executeSplit: {gas:,}')
    assert yvcrvusd.balanceOf(receiver) > amount / 2
    assert yvcrvusd.balanceOf(splitter) < 10  # Some dust may exist
    transfers = list(tx.decode_logs(crvusd.Transfer))
    for t in transfers:
        print(
            CONTRACT_NAMES.get(t.contract_address, t.contract_address), 
            CONTRACT_NAMES.get(t.sender, t.sender), 
            CONTRACT_NAMES.get(t.receiver, t.receiver), 
            f"{t.value/10**18:,.2f}"
        )

def test_allocation_scenarios(
    dev,
    splitter,
    crvusd_whale,
    ylockers_ms,
    gov,
    crvusd,
    yvcrvusd,
    reward_distributor,
    voter,
    fee_burner,
    reward_token,
    gauge_controller,
):
    voter.balance += 10**18
    snap = chain.snapshot()
    voted_gauges = [
        "0x60d3d7eBBC44Dc810A743703184f062d00e6dB7e",
        "0x85D44861D024CB7603Ba906F2Dc9569fC02083F6",
        "0xF29FfF074f5cF755b55FbB3eb10A29203ac91EA2",
        "0x79F21BC30632cd40d2aF8134B469a0EB4C9574AA",
        "0x40371aad2a24ed841316EF30938881440FD4426c",
        "0x79edc58C471Acf2244B8f93d6f425fD06A439407",
        "0x053df3e4D0CeD9a3Bf0494F97E83CE1f13BdC0E2",
        "0x05255C5BD33672b9FEA4129C13274D1E6193312d",
        "0xEEBC06d495c96E57542A6d829184A907A02ef602",
        "0x6070fBD4E608ee5391189E7205d70cc4A274c017",
        "0x138cC21D15b7A06F929Fc6CFC88d2b830796F4f1",
        "0x8D867BEf70C6733ff25Cc0D1caa8aA6c38B24817",
        "0xd03BE91b1932715709e18021734fcB91BB431715",
        "0x95f00391cB5EebCd190EB58728B4CE23DbFa6ac1",
        "0x4e6bB6B7447B7B2Aa268C16AB87F4Bb48BF57939",
        "0x4Fc86cd0F9b650280Fa783e3116258e0E0496A2c",
        "0xd8b712d29381748dB89c36BCa0138d7c75866ddF",
        "0x41eBf0bEC45642A675e8b7536A2cE9c078A814B4",
        "0x222D910ef37C06774E1eDB9DC9459664f73776f0",
        "0x1Cfabd1937e75E40Fa06B650CB0C8CD233D65C20",
        "0x6A7b02338A0A7152e08f768c46D9Dd837c35C2df",
        "0xf9CB3854A922655004022A84Ba1618B1100CBEEf",
    ]

    title = f"DO NOTHING"
    print_splits(title, splitter, splitter.getSplits())
    append_to_dataframe(title, splitter, splitter.getSplits())

    title = f"REMOVE VOTES FOR YCRV GAUGES"
    num_ycrv = splitter.ycrvGaugesLength()
    ycrv_gauges = [splitter.ycrvGauges(i) for i in range(num_ycrv)]
    for g in voted_gauges:
        if g not in ycrv_gauges:
            continue
        tx = gauge_controller.vote_for_gauge_weights(g, 0, sender=voter)
    print_splits(title, splitter, splitter.getSplits())
    append_to_dataframe(title, splitter, splitter.getSplits())
    chain.restore(snap)
    snap = chain.snapshot()

    title = f"REMOVE VOTES FOR PARTNER GAUGES"
    num_partner = splitter.partnerGaugesLength()
    partner_gauges = [splitter.partnerGauges(i) for i in range(num_partner)]
    for g in voted_gauges:
        if g not in partner_gauges:
            continue
        tx = gauge_controller.vote_for_gauge_weights(g, 0, sender=voter)
    print_splits(title, splitter, splitter.getSplits())
    append_to_dataframe(title, splitter, splitter.getSplits())
    chain.restore(snap)
    snap = chain.snapshot()

    num_discretionary = splitter.discretionaryGaugesLength()
    discretionary_gauges = [
        splitter.discretionaryGauges(i) for i in range(num_discretionary)
    ]
    for g in voted_gauges:
        if g in discretionary_gauges:
            continue
        tx = gauge_controller.vote_for_gauge_weights(g, 0, sender=voter)
    title = f"REMOVE VOTES FOR DISCRETIONARY VOTES"
    print_splits(title, splitter, splitter.getSplits())
    append_to_dataframe(title, splitter, splitter.getSplits())
    chain.restore(snap)
    snap = chain.snapshot()

    for g in voted_gauges:
        if g not in discretionary_gauges:
            continue
        tx = gauge_controller.vote_for_gauge_weights(g, 0, sender=voter)
    title = f"REMOVE ALL VOTES EXCEPT DISCRETIONARY"
    print_splits(title, splitter, splitter.getSplits())
    append_to_dataframe(title, splitter, splitter.getSplits())
    chain.restore(snap)
    snap = chain.snapshot()

    title = f"REMOVE ALL VOTES"
    for g in voted_gauges:
        tx = gauge_controller.vote_for_gauge_weights(g, 0, sender=voter)

    assert gauge_controller.vote_user_power(voter) == 0
    print_splits(title, splitter, splitter.getSplits())
    append_to_dataframe(title, splitter, splitter.getSplits())

    title = f"100% OF VOTE WEIGHT TO DISCRETIONARY"
    d = "0x36152AA234fcF97b5C14Fc6d4893fC0dA5328BD2"  # Randomly selected gauge
    splitter.setDiscretionaryGauges([d], sender=gov)
    tx = gauge_controller.vote_for_gauge_weights(d, 10_000, sender=voter)
    # Group bias will be greater than ve balance
    # Must advance to next week to avoid reverting on this edge case
    week_start = int(chain.pending_timestamp / WEEK) * WEEK
    chain.pending_timestamp = week_start + WEEK
    chain.mine()
    try:
        splits = splitter.getSplits()
    except:
        splits = "REVERT"
    print_splits(title, splitter, splits)
    append_to_dataframe(title, splitter, splits)

    # assert False
    # assert False
    base = splitter.getBaseBalances()
    # splitter.getVoteIncentiveSplitRatios(base)
    splitter.getDiscretionaryVotes()
    chain.restore(snap)
    snap = chain.snapshot()

    # Remove from stake
    title = f"EXIT ALL YCRV FROM YBS"
    ybs = Contract("0xE9A115b77A1057C918F997c32663FdcE24FB873f")
    ybs_account = accounts[ybs.address]
    ybs_account.balance += 10**18
    token = Contract(ybs.stakeToken())
    token.transfer(gov, token.balanceOf(ybs), sender=ybs_account)
    try:
        splits = splitter.getSplits()
    except:
        splits = "REVERT"
    print_splits(title, splitter, splits)
    append_to_dataframe(title, splitter, splits)
    try:
        export_to_csv("data/test_scenarios.csv")
    except:
        print("😅 No directory for data, probably means you're not wavey!")


def print_splits(title, splitter, splits):
    if splits == "REVERT":
        print(f"🚨🚨🚨🚨🚨 REVERT ON {title}")
        return
    admin_split = splits.adminFeeSplits
    voteIncentive_split = splits.voteIncentiveSplits
    print(f"{title}")
    print("-- Admin Fees --")
    print(f"{admin_split[0] / 1e16:,.2f}% YBS")
    print(f"{admin_split[1] / 1e16:,.2f}% Treasury")
    print(f"{admin_split[2] / 1e16:,.2f} Leftover")
    print("\n-- Vote Incentives --")
    print(f"{voteIncentive_split[0] / 1e16:,.2f}% YBS")
    print(f"{voteIncentive_split[1] / 1e16:,.2f}% Treasury")
    print(f"{voteIncentive_split[2] / 1e16:,.2f}% Leftover")


def test_add_invalid_gauge(splitter, gov):
    valid_gauges = [
        "0x60d3d7eBBC44Dc810A743703184f062d00e6dB7e",
        "0x85D44861D024CB7603Ba906F2Dc9569fC02083F6",
    ]
    invalid_gauges = [splitter.address]

    tx = splitter.setYCrvGauges(valid_gauges, sender=gov)

    with ape.reverts():
        # Should revert due to duplicates
        tx = splitter.setYCrvGauges(valid_gauges + valid_gauges, sender=gov)
    with ape.reverts():
        # Should revert due to unapproved by curve gov
        tx = splitter.setYCrvGauges(invalid_gauges, sender=gov)

def test_change_roles (
    splitter,
    dev,
    ylockers_ms,
    gov,
):
    
    with ape.reverts():
        # Should revert due to duplicates
        tx = splitter.setGuardian(ylockers_ms, sender=ylockers_ms)
        tx = splitter.setGuardian(ZERO_ADDRESS, sender=gov)

    tx = splitter.setGuardian(dev, sender=gov)
    assert splitter.guardian() == dev.address
    
    with ape.reverts():
        # Should revert due to duplicates
        tx = splitter.setOwner(ylockers_ms, sender=ylockers_ms)
        tx = splitter.setGuardian(ZERO_ADDRESS, sender=gov)

    tx = splitter.setOwner(ylockers_ms, sender=gov)
    assert splitter.owner() == ylockers_ms.address

    tx = splitter.setOwner(gov, sender=ylockers_ms)
    tx = splitter.setGuardian(ylockers_ms, sender=gov)


def append_to_dataframe(title, splitter, splits):
    global df  # Access the global DataFrame

    if splits == "REVERT":
        print(f"🚨🚨🚨🚨🚨 REVERT ON {title}")
        new_row_df = pd.DataFrame(
            {
                "Scenarios": [title],
                "Admin Fee % YBS": ["🚨 Revert!"],
                # Provide default values for other columns if they exist in df to ensure schema alignment
            }
        )
    else:
        admin_split = splits.adminFeeSplits
        voteIncentive_split = splits.voteIncentiveSplits

        # Creating a new DataFrame from data dictionary for the row
        new_row_df = pd.DataFrame(
            {
                "Scenarios": [title],
                "Admin Fee % YBS": [admin_split[0] / 1e16],
                "Admin Fee % Treasury": [admin_split[1] / 1e16],
                "Admin Fee % Leftover": [admin_split[2] / 1e16],
                "Vote Incentive % YBS": [voteIncentive_split[0] / 1e16],
                "Vote Incentive % Treasury": [voteIncentive_split[1] / 1e16],
                "Vote Incentive % Leftover": [voteIncentive_split[2] / 1e16],
            }
        )

    # Concatenate the new row dataframe to the existing dataframe
    df = pd.concat([df, new_row_df], ignore_index=True)

    # Optionally, print the DataFrame to see updated rows
    print(df)


def export_to_csv(file_path):
    global df
    df.to_csv(file_path, index=False)
    print(f"Data exported to {file_path}")

def can_checkpoint(new_fee_distributor, ts):
    can = new_fee_distributor.can_checkpoint_token()
    next = new_fee_distributor.last_token_time() + DAY
    if can and ts > next:
        return True
    return False