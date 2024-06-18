import pytest
import ape
from ape import chain, Contract
from ape.utils import ZERO_ADDRESS

# Accounts
@pytest.fixture(scope="session")
def dev(accounts):
    yield accounts[0]

@pytest.fixture(scope="session")
def receiver1(project, dev, ylockers_ms):
    yield dev.deploy(project.Receiver1, ylockers_ms)

@pytest.fixture(scope="session")
def splitter(project, dev, receiver1, ylockers_ms):
    splitter = dev.deploy(project.YCRVSplitter, receiver1)
    crvusd = splitter.CRVUSD()
    receiver1.setTokenApproval(crvusd, splitter, 2**256-1, sender=ylockers_ms)
    yield splitter

@pytest.fixture(scope="session")
def reward_distributor(splitter):
    yield Contract(splitter.REWARD_DISTRIBUTOR())

@pytest.fixture(scope="session")
def crvusd():
    yield Contract('0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E')

@pytest.fixture(scope="session")
def gauge_controller():
    yield Contract('0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB')
    

@pytest.fixture(scope="session")
def yvcrvusd(splitter):
    yield Contract(splitter.REWARD_TOKEN())

@pytest.fixture(scope="session")
def reward_token(splitter):
    yield Contract(splitter.REWARD_TOKEN())

@pytest.fixture(scope="session")
def new_fee_distributor():
    yield Contract('0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914')

@pytest.fixture(scope="session")
def voter(splitter):
    yield Contract(splitter.VOTER())

@pytest.fixture(scope="session")
def crvusd_whale(accounts):
    whale = accounts['0xA920De414eA4Ab66b97dA1bFE9e6EcA7d4219635']
    whale.balance += 10 ** 18
    yield whale

@pytest.fixture(scope="session")
def curve_dao(accounts):
    curve_dao = accounts['0x40907540d8a6C65c637785e8f8B742ae6b0b9968']
    curve_dao.balance += 10 ** 18
    yield curve_dao
    

@pytest.fixture(scope="session")
def gov(accounts, splitter):
    return accounts[splitter.owner()]

@pytest.fixture(scope="session")
def ylockers_ms(accounts):
    ms = accounts['0x4444AAAACDBa5580282365e25b16309Bd770ce4a']
    ms.balance += 10 ** 18
    yield ms