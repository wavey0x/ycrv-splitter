from ape import chain, project, Contract

WEEK = 60 * 60 * 24 * 7

def test_splitter(
    dev, splitter
):
    partner_balances = 1_250_000 * 10 ** 18
    admin_split = splitter.getSplits().adminFeeSplits
    bribe_split = splitter.getSplits().bribeSplits
    
    print('-- Admin Fees --')
    print(f'{admin_split[0] / 1e16:,.2f}% YBS')
    print(f'{admin_split[1] / 1e16:,.2f}% Treasury')
    print(f'{admin_split[2] / 1e16:,.2f} Leftover')
    print('\n-- Bribes --')
    print(f'{bribe_split[0] / 1e16:,.2f}% YBS')
    print(f'{bribe_split[1] / 1e16:,.2f}% Treasury')
    print(f'{bribe_split[2] / 1e16:,.2f}% Leftover')
    assert False