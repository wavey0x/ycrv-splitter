from ape import chain, project, Contract
import ape

DAY = 24 * 60 * 60
WEEK = DAY * 7

def test_splitter(
    dev, splitter, crvusd_whale, ylockers_ms, gov, crvusd, yvcrvusd, reward_distributor,
    receiver1, receiver2, reward_token, new_fee_distributor, curve_dao, voter, mock_proxy, 
    top_up_curve_fee_distributor,
):
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

def test_remove_votes(dev, splitter, crvusd_whale, ylockers_ms, gov, crvusd, 
    yvcrvusd, reward_distributor, voter,
    receiver1, reward_token, gauge_controller
    ):

    voted_gauges = [
        '0x60d3d7eBBC44Dc810A743703184f062d00e6dB7e',
        '0x85D44861D024CB7603Ba906F2Dc9569fC02083F6',
    ]
    
    voter.balance += 10 ** 18
    tx = gauge_controller.vote_for_gauge_weights(
        splitter.ycrvGauges(0),
        0,
        sender=voter
    )
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

    # Remove from stake
    ybs = Contract('0xE9A115b77A1057C918F997c32663FdcE24FB873f')
    s = Contract('0xBdF157c3bad2164Ce6F9dc607fd115374010c5dC')
    s.emergencyUnstake(ybs.balanceOf(s), sender=gov)

    splitter.getSplits()

def test_add_invalid_gauge(splitter, gov):
    valid_gauges = [
        '0x60d3d7eBBC44Dc810A743703184f062d00e6dB7e',
        '0x85D44861D024CB7603Ba906F2Dc9569fC02083F6',
    ]
    invalid_gauges = [splitter.address]

    tx = splitter.setYCrvGauges(valid_gauges, sender=gov)

    with ape.reverts():
        # Should revert due to duplicates
        tx = splitter.setYCrvGauges(valid_gauges+valid_gauges, sender=gov)
    with ape.reverts():
        # Should revert due to unapproved by curve gov
        tx = splitter.setYCrvGauges(invalid_gauges,sender=gov)