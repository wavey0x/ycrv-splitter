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