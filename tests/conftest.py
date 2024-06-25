import pytest
import ape
from ape import chain, Contract
from ape.utils import ZERO_ADDRESS

DAY = 24 * 60 * 60
WEEK = DAY * 7

# Accounts
@pytest.fixture(scope="session")
def dev(accounts):
    yield accounts[0]


@pytest.fixture(scope="session")
def gov(accounts):
    gov = accounts["0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52"]
    gov.balance += 10**18
    yield gov


@pytest.fixture(scope="session")
def ylockers_ms(accounts):
    ms = accounts["0x4444AAAACDBa5580282365e25b16309Bd770ce4a"]
    ms.balance += 10**18
    yield ms


@pytest.fixture(scope="session")
def trade_factory(accounts):
    ms = accounts["0xb634316E06cC0B358437CbadD4dC94F1D3a92B3b"]
    ms.balance += 10**18
    yield ms


@pytest.fixture(scope="session")
def fee_burner(project, gov, ylockers_ms, trade_factory):
    print(f"GOV: {gov}")
    fee_burner = gov.deploy(project.FeeBurner, ylockers_ms)
    yield fee_burner


@pytest.fixture(scope="session")
def receiver(project, gov, ylockers_ms, reward_distributor, dev):
    yield dev.deploy(project.Receiver, gov, ylockers_ms, gov, reward_distributor)


@pytest.fixture(scope="session")
def splitter(project, dev, fee_burner, receiver, gov, crvusd):
    discretionary_gauges = [
        "0x05255C5BD33672b9FEA4129C13274D1E6193312d",  # YFI/ETH
        "0x138cC21D15b7A06F929Fc6CFC88d2b830796F4f1",  # ETH/yETH
    ]
    ycrv_gauges = [
        "0xEEBC06d495c96E57542A6d829184A907A02ef602",  # CRV/yCRV
    ]
    partner_gauges = [
        "0x6070fBD4E608ee5391189E7205d70cc4A274c017",  # Threshold
    ]
    splitter = dev.deploy(
        project.YCRVSplitter,
        fee_burner,
        receiver,
        ycrv_gauges,
        partner_gauges,
        discretionary_gauges,
    )

    # splitter needs to be an approved spender of crvUSD from fee burner
    fee_burner.approveTokenSpender(splitter, sender=gov)
    fee_burner.giveTokenAllowance(splitter, [crvusd], sender=gov)

    yield splitter


@pytest.fixture(scope="session")
def mock_proxy(accounts, project, gov, fee_burner, splitter):
    mock_proxy = gov.deploy(project.StrategyProxy, splitter)
    voter = Contract(mock_proxy.proxy())
    voter.setStrategy(mock_proxy, sender=gov)
    assert mock_proxy.adminFeeRecipient() == splitter.address
    # mock_proxy.setAdminFeeRecipient(fee_burner, sender=gov)
    yield mock_proxy


@pytest.fixture(scope="session")
def reward_distributor():
    yield Contract("0xB226c52EB411326CdB54824a88aBaFDAAfF16D3d")


@pytest.fixture(scope="session")
def crvusd():
    yield Contract("0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E")


@pytest.fixture(scope="session")
def crv():
    yield Contract("0xD533a949740bb3306d119CC777fa900bA034cd52")


@pytest.fixture(scope="session")
def spell():
    yield Contract("0x090185f2135308BaD17527004364eBcC2D37e5F6")


@pytest.fixture(scope="session")
def gauge_controller():
    yield Contract("0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB")


@pytest.fixture(scope="session")
def yvcrvusd(splitter):
    yield Contract(splitter.REWARD_TOKEN())


@pytest.fixture(scope="session")
def reward_token(splitter):
    yield Contract(splitter.REWARD_TOKEN())


@pytest.fixture(scope="session")
def new_fee_distributor():
    yield Contract("0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914")


@pytest.fixture(scope="session")
def voter(splitter, accounts):
    voter = accounts[splitter.VOTER()]
    voter.balance += 10**18
    yield voter


@pytest.fixture(scope="session")
def crvusd_whale(accounts):
    whale = accounts["0xA920De414eA4Ab66b97dA1bFE9e6EcA7d4219635"]
    whale.balance += 10**18
    yield whale


@pytest.fixture(scope="session")
def crv_whale(accounts):
    whale = accounts["0xF977814e90dA44bFA03b6295A0616a897441aceC"]
    whale.balance += 10**18
    yield whale


@pytest.fixture(scope="session")
def spell_whale(accounts):
    whale = accounts["0xF977814e90dA44bFA03b6295A0616a897441aceC"]
    whale.balance += 10**18
    yield whale


@pytest.fixture(scope="session")
def curve_dao(accounts):
    curve_dao = accounts["0x40907540d8a6C65c637785e8f8B742ae6b0b9968"]
    curve_dao.balance += 10**18
    yield curve_dao


@pytest.fixture(scope="function")
def top_up_curve_fee_distributor(
    new_fee_distributor, mock_proxy, crvusd, crvusd_whale, curve_dao, dev
):
    assert new_fee_distributor.address == mock_proxy.feeDistribution()

    def top_up_curve_fee_distributor(
        new_fee_distributor=new_fee_distributor,
        crvusd=crvusd,
        crvusd_whale=crvusd_whale,
        dev=dev,
    ):
        crvusd.transfer(new_fee_distributor, 100_000 * 10**18, sender=crvusd_whale)
        if not new_fee_distributor.can_checkpoint_token():
            new_fee_distributor.toggle_allow_checkpoint_token(sender=curve_dao)
        new_fee_distributor.checkpoint_token(sender=dev)
        chain.pending_timestamp += WEEK
        chain.mine()
        # new_fee_distributor.checkpoint_token(sender=dev)

    yield top_up_curve_fee_distributor
