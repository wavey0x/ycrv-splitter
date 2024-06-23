import ape
from ape import Contract
import pytest


PRECISION = 10**18


def test_fee_burner(
    chain,
    fee_burner,
    trade_factory,
    ylockers_ms,
    gov,
    dev,
    crvusd,
    crvusd_whale,
    crv,
    crv_whale,
    spell,
    spell_whale,
):
    # stock our fee distributor w/ good tokens
    crvusd.transfer(fee_burner, 10_000 * PRECISION, sender=crvusd_whale)
    crv.transfer(fee_burner, 10_000 * PRECISION, sender=crv_whale)
    spell.transfer(fee_burner, 10_000 * PRECISION, sender=spell_whale)

    spell_starting = spell.balanceOf(fee_burner)
    crv_starting = crv.balanceOf(fee_burner)
    crvusd_starting = crvusd.balanceOf(fee_burner)

    # check that an unapproved factory can't do anything
    assert fee_burner.isTokenSpender(trade_factory) == False
    with ape.reverts("revert: Ownable: caller is not the owner"):
        fee_burner.approveTokenSpender(trade_factory, sender=ylockers_ms)

    # approve trade factory as a spender
    fee_burner.approveTokenSpender(trade_factory, sender=gov)
    assert fee_burner.isTokenSpender(trade_factory) == True

    # still can't pull out tokens
    with ape.reverts():
        crv.transferFrom(
            fee_burner, trade_factory, 10_000 * PRECISION, sender=trade_factory
        )
    with ape.reverts():
        crvusd.transferFrom(
            fee_burner, trade_factory, 10_000 * PRECISION, sender=trade_factory
        )
    with ape.reverts("revert: ERC20: allowance too low"):
        spell.transferFrom(
            fee_burner, trade_factory, 10_000 * PRECISION, sender=trade_factory
        )

    # trade factory can't give themselves new token approvals!
    with ape.reverts("revert: not approved"):
        fee_burner.giveTokenAllowance(
            trade_factory, [crv, crvusd], sender=trade_factory
        )

    # accidentally pass in our own address, whoops
    with ape.reverts("revert: unapproved spender"):
        fee_burner.giveTokenAllowance(ylockers_ms, [crv, crvusd], sender=ylockers_ms)

    # give approval for crv and crvUSD
    fee_burner.giveTokenAllowance(trade_factory, [crv, crvusd], sender=ylockers_ms)
    print(
        "\nCRV Approval amount:",
        crv.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "crvUSD Approval amount:",
        crvusd.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "SPELL Approval amount:",
        spell.allowance(fee_burner, trade_factory) / PRECISION,
        "\n",
    )

    # should be able to pull out crv and crvUSD, not spell
    to_pull = 1_000 * PRECISION
    crv.transferFrom(fee_burner, trade_factory, to_pull, sender=trade_factory)
    assert crv.balanceOf(fee_burner) == crv_starting - to_pull
    crv_current = crv.balanceOf(fee_burner)
    crvusd.transferFrom(fee_burner, trade_factory, to_pull, sender=trade_factory)
    assert crvusd.balanceOf(fee_burner) == crvusd_starting - to_pull
    crvusd_current = crvusd.balanceOf(fee_burner)
    with ape.reverts("revert: ERC20: allowance too low"):
        spell.transferFrom(
            fee_burner, trade_factory, 10_000 * PRECISION, sender=trade_factory
        )

    # check the approvals we currently have
    approvals = fee_burner.getApprovals(trade_factory)
    print("Trade Factory approvals:", approvals)
    assert len(approvals) == 2
    approvals = fee_burner.getApprovals(ylockers_ms)
    print("yLockers approvals:", approvals)
    assert len(approvals) == 0

    # make sure nothing happens if we accidentally re-approve
    fee_burner.giveTokenAllowance(trade_factory, [crv, crvusd], sender=ylockers_ms)
    print("\nRe-give the same token allowances")
    print(
        "CRV Approval amount:",
        crv.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "crvUSD Approval amount:",
        crvusd.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "SPELL Approval amount:",
        spell.allowance(fee_burner, trade_factory) / PRECISION,
        "\n",
    )

    # revoke a token allowance. doesn't necessarily have to be for a spender.
    fee_burner.revokeTokenAllowance(trade_factory, [crv], sender=ylockers_ms)
    print("\nRevoke allowance for only CRV")
    print(
        "CRV Approval amount:",
        crv.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "crvUSD Approval amount:",
        crvusd.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "SPELL Approval amount:",
        spell.allowance(fee_burner, trade_factory) / PRECISION,
        "\n",
    )

    # we should be able to revoke for an address with no approvals too, and also for tokens with no approval
    fee_burner.revokeTokenAllowance(trade_factory, [spell, crv], sender=ylockers_ms)
    fee_burner.revokeTokenAllowance(ylockers_ms, [spell, crv], sender=gov)
    print("\nCheck after revoking already revoked tokens")
    print(
        "CRV Approval amount:",
        crv.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "crvUSD Approval amount:",
        crvusd.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "SPELL Approval amount:",
        spell.allowance(fee_burner, trade_factory) / PRECISION,
        "\n",
    )

    print("\nCheck yLockers MS (non-spender) approvals after revoking them")
    print(
        "CRV Approval amount:",
        crv.allowance(fee_burner, ylockers_ms) / PRECISION,
    )
    print(
        "crvUSD Approval amount:",
        crvusd.allowance(fee_burner, ylockers_ms) / PRECISION,
    )
    print(
        "SPELL Approval amount:",
        spell.allowance(fee_burner, ylockers_ms) / PRECISION,
        "\n",
    )

    # make sure we can re-grant approvals to spender
    fee_burner.giveTokenAllowance(trade_factory, [spell, crv, crvusd], sender=gov)
    print("\nCheck after re-giving and adding approvals for trade factory")
    print(
        "CRV Approval amount:",
        crv.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "crvUSD Approval amount:",
        crvusd.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "SPELL Approval amount:",
        spell.allowance(fee_burner, trade_factory) / PRECISION,
        "\n",
    )

    # check then revoke trade factory's spender status and approvals, bad trade factory!
    approvals = fee_burner.getApprovals(trade_factory)
    print("Trade Factory approvals:", approvals)
    assert len(approvals) == 3

    # not just anyone can revert their approval
    with ape.reverts("revert: not approved"):
        fee_burner.revokeTokenSpender(trade_factory, sender=dev)

    # can't revoke an address that isn't a spender
    with ape.reverts("revert: not a spender"):
        fee_burner.revokeTokenSpender(ylockers_ms, sender=gov)

    fee_burner.revokeTokenSpender(trade_factory, sender=ylockers_ms)
    assert fee_burner.isTokenSpender(trade_factory) == False
    approvals = fee_burner.getApprovals(trade_factory)
    print("Trade Factory approvals:", approvals)
    assert len(approvals) == 0

    print("\nCheck after removing trade factory as a spender")
    print(
        "CRV Approval amount:",
        crv.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "crvUSD Approval amount:",
        crvusd.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "SPELL Approval amount:",
        spell.allowance(fee_burner, trade_factory) / PRECISION,
        "\n",
    )

    # update guardian role, make sure only owner can
    with ape.reverts("revert: Ownable: caller is not the owner"):
        fee_burner.setGuardian(dev, sender=dev)
    fee_burner.setGuardian(dev, sender=gov)

    # ylockers ms should be locked out now
    with ape.reverts("revert: not approved"):
        fee_burner.giveTokenAllowance(trade_factory, [crv, crvusd], sender=ylockers_ms)

    # now some random dev has the power
    with ape.reverts("revert: unapproved spender"):
        fee_burner.giveTokenAllowance(trade_factory, [crv, crvusd], sender=dev)

    # gov still has the approve new spenders
    with ape.reverts("revert: Ownable: caller is not the owner"):
        fee_burner.approveTokenSpender(trade_factory, sender=dev)
    fee_burner.approveTokenSpender(trade_factory, sender=gov)

    fee_burner.giveTokenAllowance(trade_factory, [crv, crvusd], sender=dev)
    print("\nReenable trade factory again after removing them as a spender")
    print(
        "CRV Approval amount:",
        crv.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "crvUSD Approval amount:",
        crvusd.allowance(fee_burner, trade_factory) / PRECISION,
    )
    print(
        "SPELL Approval amount:",
        spell.allowance(fee_burner, trade_factory) / PRECISION,
        "\n",
    )
