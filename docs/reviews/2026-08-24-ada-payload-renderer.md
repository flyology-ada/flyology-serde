# Ada payload renderer review

Date: 2026-08-24

Scope: the test-gated Ada lowered-record owner and deterministic in-memory payload renderer. This milestone does
not include Type IR loading, attestation headers, manifests, filesystem publication, or a successful CLI path.

Architecture review required the following boundaries:

- the fixed model constructor exists only in the nested test source directory and accepts no overlay or persisted
  Type IR data;
- production `Generation.Generate` remains fail-closed and publishes nothing;
- the renderer emits only the two Ada payloads after the attestation header, never a header or manifest;
- output files, per-file bytes, aggregate bytes, observed model items, and rendered-byte work are charged exactly
  once; each output chunk is charged before it is scanned or appended, while denied charges poison the operation
  budget;
- a private candidate is validated completely before a nonallocating owner swap, so failure cannot replace an
  earlier result;
- migration compares exact bytes after validating and removing exactly seven legacy header lines from both fresh
  Python output and the checked-in golden.

Architecture review: P0 none after excluding fixture construction from production sources and excluding v2
attestation and publication. P1 and P2 requirements above were incorporated before implementation.

Change review: P0 none. Two P1 findings required correction: the original two-pass renderer performed uncharged
measurement and materialization work, and model validation did not prove every derived line fit the 110-column
limit before output charging. P2 findings requested a bounded payload-copy API, stronger malformed-model and exact
header tests, explicit copy preservation, and complete process documentation.

The fixes use one transactional pass. Both file slots are reserved first; every output chunk charges exact file,
aggregate-byte, and work counters before append. The candidate owns payload storage directly, so commit does not
copy or allocate payload bytes. Validation checks every dynamic emitted use site before the first charge, with
accepted/rejected exact line-boundary tests. Internal, allocation, and unexpected failures poison the budget;
resource denial already poisons at the failed charge. Payload observation uses length plus a caller buffer, and
insufficient capacity preserves the buffer and written count. The current v1 seven-line parser checks exact labels,
lowercase digest widths, line count, CR rejection, and negative mutations.

Fix review: P0 none, P1 none, P2 none. The reviewer matched every model-dependent emitted line to prevalidation,
confirmed the exact 110/111 boundary cases, verified that every post-charge failure path poisons the budget, and
confirmed candidate publication remains one pointer swap after both payload checks. Deterministic `Storage_Error`
or unexpected-exception injection is not added in this slice: those handlers are direct nonbranching
discard/poison/status paths, while a production test hook would expand the reviewed authority surface. Resource
denial, unsupported-model rejection, poisoned reuse, prior-owner preservation, exact capacity, bounded copying,
and header rejection all have direct tests.
