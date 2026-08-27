# Installed-client round-trip proposal

Date: 2026-08-27

Status: implemented; architecture, change, fix, and final staged reviews report
P0/P1/P2 none. The slice is approved for a local commit.

## Problem

The isolated install gate currently compiles a client that only `with`s
`Flyology_Serde.Deserializers.JSON` and then does nothing. It proves that one
public unit is discoverable and that the private handwritten JSON oracle is
absent, but it does not prove that an external Ada application can use the
installed library to serialize, deserialize, link, and run. Internal tests can
pass while installed project metadata, public generic visibility, or linked
artifacts remain unusable.

## Proposed external program

Replace the no-op body of `Public_JSON_Client` with one self-contained external
application that uses only installed public units. Keep the historical source
name because the same isolated project also tests rejection of the private
JSON oracle, but exercise both maintained formats.

The program defines a small record containing an unsigned identifier and a
Boolean. It instantiates the public unsigned-integer leaf adapter and the
public record combinator with bounded, nonallocating metadata callbacks. One
root serialization adapter and one transactional root deserialization adapter
are shared by JSON and CBOR.

For each format the executable must:

1. serialize the record through a bounded writer under explicit limits;
2. copy only committed output into an arbitrary-lower-bound caller buffer;
3. deserialize those exact copied bytes through a borrowed bounded reader
   configured with the root adapter's exact policy;
4. publish the builder candidate only after complete-document validation; and
5. check the complete round trip, clean path, writer/reader completion, and
   exact expected JSON presentation. CBOR output is checked by the same typed
   round trip rather than assigned a new persistent byte identity.

The JSON negative fixture is exactly `{"identifier":9}`: one valid field
mutates only the candidate and the required Boolean field is then missing. The
client requires `Missing_Field`, a one-element `enabled` field path, no commit,
one rollback, cleared candidate-ready and field-presence state, reset candidate
field values, unchanged published sentinel, and reader incompleteness. It then
calls `Errors.Reset`, performs one public reader read or peek before
`Reader.Reset`, and requires a fresh `Invalid_State` with publication and the
clean candidate still unchanged. After another `Errors.Reset`, it resets the
same reader over the same immutable input and requires the same late failure,
a second rollback, cleared candidate and presence state, and publication still
unchanged.
This is one application-level transaction check, not a new backend
conformance suite.

The external project imports only `flyology_serde`, not `flyology_json`.
Flyology JSON remains staged, but it must be discovered through the installed
Serde project dependency closure. The first implementation run exposed that
the checkout project imported Flyology JSON only through Alire's generated
abstract config project, while `gprinstall` did not retain that indirect import
in the installed `flyology_serde.gpr`. The root `flyology_serde.gpr` therefore
adds a direct project import of `flyology_json.gpr` alongside its config import,
making the runtime dependency explicit to both checkout and installed
consumers. The gate inspects the generated installed project for that import
before building the client. Inspection requires exactly one generated staged
`flyology_serde.gpr`, an anchored top-level `with "flyology_json";` in
`gprinstall`'s normalized generated syntax rather than a comment or config-only
import, and the corresponding staged `flyology_json.gpr`. A redundant direct
client import would mask the project-metadata failure this gate is meant to
prevent.

The fixture supplies complete explicit aggregates: all five serialization
limits; all six decode limits; unknown-, duplicate-field, and duplicate-key
actions; writer capacities; record/type/name/alias maxima; and the exact root
deserializer policy actual. It uses no generic default or `others => <>` for a
resource or semantic policy. The exact JSON expectation is a hard-coded
literal independent of the metadata callbacks.

The project keeps `-gnata`, but every verdict uses a local `Require` operation
that explicitly raises on false. Correctness therefore cannot disappear if an
assertion switch drifts. The install script must verify and execute the exact
fresh `$stage/bin/public_json_client` after compiling it and before separately
proving that the private handwritten-oracle child cannot compile.

Positive build/link, execution, and negative compilation run under `env -i`
with only an explicit toolchain/system PATH, fresh HOME and TMPDIR,
`GPR_PROJECT_PATH` equal to the staged GPR directory, a fixed locale, and
explicit static `LIBRARY_TYPE`, `FLYOLOGY_JSON_LIBRARY_TYPE`, and
`FLYOLOGY_SERDE_LIBRARY_TYPE`. No Ada include, object, project, library,
loader, or checkout path is inherited. Compiler and runtime system defaults
remain permitted. Both builds use the staged project path rather than `-aP`,
and execution names the absolute staged binary rather than searching PATH.

Before that isolated client phase, one clean static Serde build covers its
direct Flyology JSON dependency, and one recursive `gprinstall -r` from Serde
installs that explicit closure. There is no separate JSON install and therefore
no duplicate dependency overwrite or order-dependent ownership. The build and
install use the same explicit static library selection, and the gate requires
exactly one staged project and static library for each crate. Inherited
build-kind state therefore cannot choose the artifacts staged for the later
clean-environment check.

Each committed output is copied twice: once into an aliased exact-length
buffer ending at the index type's maximum value, and once into a larger
arbitrary-lower-bound buffer whose unused tail is prefilled and verified as
spaces or zeroes. A limited reader is declared inside the exact buffer's scope
and borrows that stable aliased owner; no access to a temporary slice escapes.
Every last-index expression uses `First + (Length - 1)` only after proving a
nonzero length.

This exact-bound test exposes an existing public JSON writer correctness bug:
`Copy_Output` currently evaluates `Target'First + Self.Length - 1`, whose
left-associative intermediate can overflow for a valid exact-size target ending
at `Positive'Last`. This slice explicitly restores the public operation's
contract for that legal boundary case by changing the expression to
`Target'First + (Self.Length - 1)` inside the existing positive-length branch.
The case succeeds instead of leaking `Constraint_Error`; no declaration,
encoding, ordinary successful result, or error-status policy changes.

`JSON_Writer_Tests` gains a focused regression independent of the installed
client. It copies one completed document into both an exact-length `String` and
a larger `String` ending at `Positive'Last`, requires no exception, exact
reported length and bytes, and the writer's documented blank fill in the
unused larger tail. The installed client retains its own maximum-bound case to
prove the same public operation through staged artifacts.

## Boundaries

This milestone changes the root GPR's declaration of the existing Flyology
JSON dependency, the isolated external-client fixture, its project switches,
the install-gate script, the overflow-safe JSON output-index expression,
focused tests, and review documentation. It does not add or update a
dependency and does not change the Ada runtime API, JSON/CBOR encoding,
generator, Type IR, Wire, or production authority. The client must not import a
private Serde unit, a Flyology JSON implementation unit, generated fixture
code, or a checkout-relative project.

The application uses public generic adapters rather than duplicating the JSON
or CBOR syntax. Its field names are presentation policy local to this test and
are not wire tags or Type IR identities.

## Required evidence

Before commit:

1. mandatory architecture review closes every P0/P1/P2 before source changes;
2. the staged install contains no test-only/oracle artifact and the external
   client compiles, links, and executes successfully using only staged GPRs;
   its generated installed Serde GPR directly imports Flyology JSON;
3. the negative oracle client still fails for exactly the missing private unit;
4. direct internal runtime tests, root build, dependency-lock checks, generator
   gates, pinned formatting, line-length, shell, diff, and APM audit remain
   green; and
5. independent change, fix, and final staged-diff reviews report P0/P1/P2 none.

## Review and verification record

The architecture reviews initially found isolation, negative-transaction,
maximum-bound, static-selection, and installed-dependency-closure gaps. Each
was corrected before implementation. The first isolated execution then exposed
the missing direct dependency in the generated installed Serde project. The
architecture was expanded and re-reviewed before the root GPR changed.

The implementation review found one P1: the fixture rollback counter could
overflow despite the root adapter's nonraising cleanup contract. It now
saturates. P2 findings required the Flyology JSON-specific static selector,
accurate review status, and removal of unrelated formatter churn. Independent
fix and final staged re-reviews report P0/P1/P2 none.

The following gates pass on the reviewed tree:

- focused public-client JSON/CBOR execution and `JSON_Writer_Tests`;
- root `alr build` and the complete assertion-enabled Ada test action;
- isolated static recursive install, public-client build/run, private-oracle
  rejection, and test-hook elision;
- both Flyology JSON lock attestations and all ten dependency tests;
- all twelve transitional Python generator tests;
- Ada generator build, scaffold tests, smoke and lifecycle tests;
- release-marker, fixture-manifest, and generated JSON/CBOR round-trip gates;
- pinned GNATformat on changed Ada, shell syntax, `git diff --check`, and the
  explicit 110-column handwritten-Ada scan; and
- APM 0.28.0 cache-only audit with all ten checks passing.
