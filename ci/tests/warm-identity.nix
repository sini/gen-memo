# `identitiesHeld` — the plane's third decision, over two identity maps.
#
# It is reached HERE the way the evaluator reaches it: off the `warmDecision` record, not as a second
# entry point on the library root. Building the record needs an accessor and a prior facade, and
# neither is touched by this decision — the whole input is the two maps, which is what makes the
# function testable without an evaluation at all.
#
# THE MEMBERSHIP TEST IS "PRESENT IN BOTH", and two of the cells below exist only to pin that. An
# instance that APPEARS between the two evaluations has not moved and neither has one that
# disappears; both are edits this predicate is deliberately silent about, and a predicate that keyed
# on the symmetric difference instead would refuse every ordinary registry growth.
{ genMemo, ... }:
let
  # Neither field is read by `identitiesHeld`; they are supplied because the record's shape is the
  # interface and reaching the decision through a hand-built attrset would be testing a copy of it.
  decision = genMemo.warmDecision {
    accessor = {
      nodes = [ ];
      dependencies = _: [ ];
    };
    prior.resolutional = _: [ ];
  } [ ];

  held = decision.identitiesHeld;

  pewter = "thimble:0000000000000000000000000000000000000000000000000000000000000001";
  pewterMoved = "thimble:0000000000000000000000000000000000000000000000000000000000000002";
  damask = "thimble:0000000000000000000000000000000000000000000000000000000000000003";
in
{
  flake.tests.warm-identity = {
    test-identical-maps-admit = {
      expr = held {
        priorIdentities = {
          "hosts.damask" = damask;
          "hosts.pewter" = pewter;
        };
        nextIdentities = {
          "hosts.damask" = damask;
          "hosts.pewter" = pewter;
        };
      };
      expected = [ ];
    };

    # An instance only the NEXT evaluation has. Nothing moved — there is no prior identity to have
    # moved from.
    test-an-added-instance-admits = {
      expr = held {
        priorIdentities."hosts.pewter" = pewter;
        nextIdentities = {
          "hosts.damask" = damask;
          "hosts.pewter" = pewter;
        };
      };
      expected = [ ];
    };

    # An instance only the PRIOR evaluation has. Also not a move, and the arm that catches a
    # predicate written over `attrNames prior` without the membership test — that one would compare
    # a present identity against a missing attribute and abort rather than admit.
    test-a-removed-instance-admits = {
      expr = held {
        priorIdentities = {
          "hosts.damask" = damask;
          "hosts.pewter" = pewter;
        };
        nextIdentities."hosts.pewter" = pewter;
      };
      expected = [ ];
    };

    # The empty case, which is every evaluation that mints nothing: the decision is total over it and
    # costs nothing.
    test-empty-maps-admit = {
      expr = held {
        priorIdentities = { };
        nextIdentities = { };
      };
      expected = [ ];
    };
  };

  flake.testsError.warm-identity = {
    # The refusal, with every field it names pinned. `remerged` is the evaluator's vocabulary for the
    # contributing side and travels into the message unchanged; the kind is read off the identity
    # itself, so no caller can supply one that disagrees with the datum.
    test-a-moved-identity-refuses-by-name = {
      expr = held {
        priorIdentities = {
          "hosts.damask" = damask;
          "hosts.pewter" = pewter;
        };
        nextIdentities = {
          "hosts.damask" = damask;
          "hosts.pewter" = pewterMoved;
        };
        remerged = [
          "hosts"
          "schema"
        ];
      };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-memo\\.identitiesHeld: minted identity moved on a warm re-compose at 'hosts\\.pewter' \\(kind 'thimble', was '${pewter}', now '${pewterMoved}', re-merged declarations: hosts, schema, 1 instance\\(s\\) moved\\)$";
      };
    };

    # `remerged` is defaulted, so the refusal is total over an evaluator that supplies no contributing
    # side at all — it names an empty list rather than failing on a missing argument.
    test-a-moved-identity-refuses-without-a-contributing-side = {
      expr = held {
        priorIdentities."hosts.pewter" = pewter;
        nextIdentities."hosts.pewter" = pewterMoved;
      };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-memo\\.identitiesHeld: minted identity moved on a warm re-compose at 'hosts\\.pewter' \\(kind 'thimble', was '${pewter}', now '${pewterMoved}', re-merged declarations: , 1 instance\\(s\\) moved\\)$";
      };
    };
  };
}
