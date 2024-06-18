from ape import chain, project, Contract

WEEK = 60 * 60 * 24 * 7

def test_splitter(
    dev, splitter, crvusd_whale, ylockers_ms, gov, crvusd, yvcrvusd, reward_distributor,
    receiver1, reward_token, new_fee_distributor, curve_dao, voter
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

    rewards_before = yvcrvusd.balanceOf(reward_distributor)
    tx = splitter.executeSplit(sender=gov)
    transfers = list(tx.decode_logs(crvusd.Transfer))
    vi_split = list(tx.decode_logs(splitter.VoteIncentiveSplit))
    a_split = list(tx.decode_logs(splitter.AdminFeeSplit))
    for t in transfers:
        print(t.contract_address,t.sender,t.receiver, f'{t.value/10**18:,.2f}')
        # name_lookup(t.contract_address, receiver1, crvusd, reward_token, splitter)
    rewards_after = yvcrvusd.balanceOf(reward_distributor)
    rewards_deposited = rewards_after - rewards_before
    assert rewards_deposited == list(tx.decode_logs(reward_distributor.RewardDeposited))[0].rewardAmount
    assert crvusd.balanceOf(splitter) == 0

    # Give CRVUSD to ylockers and perform a deposit and split
    crvusd.transfer(ylockers_ms, amount, sender=crvusd_whale)
    crvusd.approve(splitter, 2**256-1, sender=ylockers_ms)
    tx = splitter.depositAdminFeesAndSplit(amount, sender=ylockers_ms)

    # Test Admin Fees Proper Flow
    new_fee_distributor.toggle_allow_checkpoint_token(sender=curve_dao)
    crvusd.transfer(new_fee_distributor, 100_000 * 10 ** 18, sender=crvusd_whale)
    assert False
    chain.pending_timestamp += WEEK
    chain.mine()
    new_fee_distributor.checkpoint_token(sender=dev)
    chain.pending_timestamp += WEEK
    chain.mine()
    tx = new_fee_distributor.claim(voter,sender=dev)

    assert False

    # Test Vote Incentive Proper Flow

def test_remove_votes(dev, splitter, crvusd_whale, ylockers_ms, gov, crvusd, yvcrvusd, reward_distributor,
    receiver1, reward_token, gauge_controller):
    gauge_controller 

def name_lookup(address, receiver1, crvusd, reward_token, splitter):
    NAMES = {
        receiver1.address: 'Receiver1',
        crvusd.address:  'crvUSD',
        reward_token.address: 'yvcrvUSD',
        splitter.address: 'Splitter',
    }
    if address in NAMES:
        return NAMES[address]
    return address