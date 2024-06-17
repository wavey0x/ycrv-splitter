import pytest
import ape
from ape import chain, Contract
from ape.utils import ZERO_ADDRESS

# Accounts
@pytest.fixture(scope="session")
def dev(accounts):
    yield accounts[0]

@pytest.fixture(scope="session")
def splitter(project, dev):
    splitter = dev.deploy(project.YCRVSplitter)
    yield splitter

@pytest.fixture(scope="session")
def reward_distributor(splitter):
    yield Contract(splitter.REWARD_DISTRIBUTOR())

@pytest.fixture(scope="session")
def crvusd(splitter):
    yield Contract(splitter.CRVUSD())

@pytest.fixture(scope="session")
def yvcrvusd(splitter):
    yield Contract(splitter.REWARD_TOKEN())

@pytest.fixture(scope="session")
def crvusd_whale(accounts):
    whale = accounts['0xA920De414eA4Ab66b97dA1bFE9e6EcA7d4219635']
    whale.balance += 10 ** 18
    yield whale

@pytest.fixture(scope="session")
def gov(accounts, splitter):
    return accounts[splitter.owner()]

@pytest.fixture(scope="session")
def ylockers_ms(accounts, splitter):
    ms = accounts[splitter.guardian()]
    ms.balance += 10 ** 18
    yield ms