# Ada build budget session review

## Scope

The future offline process runner will retain commands and results that charge one caller-owned build budget. A
plain resettable ledger lets those objects survive `Initialize` and silently charge a new session. This change adds
only private session identity to the existing generator build budget. It chooses no action limits, runs no process,
changes no command line, and does not affect the serde runtime.

A tag contains a synchronized, process-lifetime, nonreusing two-word owner token and one budget's nonwrapping U64
generation. It is a copyable private nonauthority value. A stale tag therefore cannot match a later budget even when
Ada reuses the same address. Successful first initialization mints the owner token; every successful initialization
bumps the generation, resets limits and usage, and publishes a valid active session. Ordinary poison or exhaustion
keeps the stored tag matching for cleanup ownership but prevents `Current_Session` from minting another tag.
Reinitialize invalidates the old generation. When a new budget requires a token after process token exhaustion, or
when one budget's generation is exhausted, initialization fails closed, invalidates the session, and preserves both
ceilings, both usage counters, and the generation. An already-owned budget can continue to reinitialize after the
process token source is exhausted until that budget's own generation is exhausted.

## Review and verification

The proposal review found that generation exhaustion initially left a last-generation tag matching. A distinct
`Session_Valid` bit now closes that terminal path without erasing ordinary terminal ownership. The review also
required a legal test seam. Generation exhaustion is exercised by a test-only direct child procedure of the private
budget package, which can inspect inherited private fields but is absent from the production source graph. It mints
the last-generation tag after setting the active generation to U64-last, then proves failed initialization changes
only state and validity. The corrected proposal review reports P0 none, P1 none, and P2 none.

The implementation review found that the proposed address-plus-generation owner identity depended on a future
accessibility-bound command type and was unsafe as a standalone primitive: a copied tag could outlive its budget and
match a new budget at the reused address. The implementation now uses the nonreusing process identity above. The
exact initialization exhaustion transaction is also normative in the package specification.

The fix review required deterministic proof of the two-word minter's carry and terminal branches. The exact sequence
transition and initialization publication transition are private helpers called by the synchronized production
minter and exercised by the separate test main with local near-boundary state. They expose no second live token
source, so independent numeric domains cannot collide. The tests cover carry, exactly-once terminal issuance, sticky
sequence exhaustion, continued reinitialization of an already-owned budget, and preservation on a failed new-budget
initialization without exposing a production test hook.

The narrow fix review found that an inconsistent private sequence seeded at the terminal token without its exhausted
bit could use modular arithmetic to wrap. Although the production source cannot reach that state, the transition now
detects it before arithmetic, fails closed, and keeps the failure sticky; the direct edge test covers both calls.

Ordinary tests cover default invalidity, same-session matching, two live foreign budgets at the same generation,
reinitialize invalidation, poison/exhaustion identity retention, and refusal to mint a current tag while terminal.

The implementation review initially reported P1 for address reuse in the first owner identity and P2 for missing
normative failure wording. The nonreusing token and specification contract close both. Its first fix review reported
P2 for untested carry and terminal behavior; the exact transition tests close it. The second fix review found the
inconsistent terminal seed above; the pre-arithmetic guard and sticky regression close it. The final narrow fix
review reports P0 none, P1 none, and P2 none.

Forced warning-enabled builds and the focused tests pass with GNAT 15.3.1 and 16.1.0. The complete Ada generator
smoke suite, runtime library and assertion-enabled tests, all twelve transitional Python generator tests, generated
JSON/CBOR round trips, release-marker scan, golden manifest verification, all ten APM audit checks, the diff check,
and the explicit 110-column scan pass. GNATformat was invoked through the owning test project but is not
installed in this environment; both compiler style checks passed instead. The final independent diff review follows
before commit. That review reports P0 none, P1 none, and P2 none and confirms the production provenance remains exact.
