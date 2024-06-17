from ape import chain, project, Contract

WEEK = 60 * 60 * 24 * 7

def test_splitter(
    dev, splitter, crvusd_whale, ylockers_ms, gov, crvusd, yvcrvusd, reward_distributor
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
    crvusd.transfer(splitter, amount, sender=crvusd_whale)

    rewards_before = yvcrvusd.balanceOf(reward_distributor)
    tx = splitter.executeSplit(sender=gov)
    rewards_after = yvcrvusd.balanceOf(reward_distributor)
    rewards_deposited = rewards_after - rewards_before
    assert rewards_deposited == list(tx.decode_logs(reward_distributor.RewardDeposited))[0].rewardAmount
    assert crvusd.balanceOf(splitter) == 0

    # Give CRVUSD to ylockers and perform a deposit and split
    crvusd.transfer(ylockers_ms, amount, sender=crvusd_whale)
    crvusd.approve(splitter, 2**256-1, sender=ylockers_ms)
    tx = splitter.depositAdminFeesAndSplit(amount,sender=ylockers_ms)