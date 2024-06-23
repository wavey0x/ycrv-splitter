from ape import chain, project, Contract

DAY = 24 * 60 * 60
WEEK = DAY * 7

def test_splitter(
    dev, splitter, crvusd_whale, ylockers_ms, gov, crvusd, yvcrvusd, reward_distributor,
    receiver1, receiver2, reward_token, new_fee_distributor, curve_dao, voter, mock_proxy, 
    top_up_curve_fee_distributor,
):
    partner_balances = 1_250_000 * 10 ** 18
    admin_split = splitter.getSplits().adminFeeSplits
    voteIncentive_split = splitter.getSplits().voteIncentiveSplits
    
    print('-- Admin Fees --')
    print(f'{admin_split[0] / 1e16:,.2f}% YBS')
    print(f'{admin_split[1] / 1e16:,.2f}% Treasury')
    print(f'{admin_split[2] / 1e16:,.2f} Leftover')
    print('\n-- Vote Incentives --')
    print(f'{voteIncentive_split[0] / 1e16:,.2f}% YBS')
    print(f'{voteIncentive_split[1] / 1e16:,.2f}% Treasury')
    print(f'{voteIncentive_split[2] / 1e16:,.2f}% Leftover')

    amount = 100_000 * 10 ** 18
    crvusd.transfer(receiver1, amount, sender=crvusd_whale)

    rewards_before = yvcrvusd.balanceOf(receiver2)

    before = crvusd.balanceOf(new_fee_distributor)
    top_up_curve_fee_distributor() # sends crvUSD, checkpoints, advances 1 week
    assert crvusd.balanceOf(new_fee_distributor) > before

    # if mock_proxy.lastTimeCursor() < WEEK + DAY:
    #     chain.pending_timestamp += WEEK + DAY
    #     chain.mine()

    new_fee_distributor.checkpoint_token(sender=dev)
    tx = splitter.executeSplit(sender=gov)

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
    print(f'Admin Fees {total_admin_fees:,.2f}')
    print(f'Vote Incentives {total_vote_incentives:,.2f}')
    for t in transfers:
        print(t.contract_address,t.sender,t.receiver, f'{t.value/10**18:,.2f}')

    total_rewards = yvcrvusd.balanceOf(receiver2)


    tx = receiver2.depositRewards(sender=dev)
    fee = receiver2.performanceFee() / 10_000 * total_rewards
    deposited = list(tx.decode_logs(reward_distributor.RewardDeposited))[0].rewardAmount
    assert abs(int(total_rewards) - int(fee) - deposited) < 10 ** 18
    
    assert crvusd.balanceOf(splitter) < 10 # Some dust may exist
    assert yvcrvusd.balanceOf(splitter) < 10 # Some dust may exist

    # Manual Admin fee Split
    # Give CRVUSD to ylockers and perform a deposit and split
    crvusd.transfer(ylockers_ms, amount, sender=crvusd_whale)
    crvusd.approve(splitter, 2**256-1, sender=ylockers_ms)
    tx = splitter.depositAdminFeesAndSplit(amount, sender=ylockers_ms)
    assert yvcrvusd.balanceOf(receiver2) > amount / 2
    
    assert False

def test_remove_votes(dev, splitter, crvusd_whale, ylockers_ms, gov, crvusd, yvcrvusd, reward_distributor,
    receiver1, reward_token, gauge_controller):
    return

def test_add_gauge_with_zero_votes():
    return