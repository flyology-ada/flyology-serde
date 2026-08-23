# JSON backend

The JSON backend maps every serde logical value losslessly using UTF-8 JSON. It is deterministic for one event
stream but does not sort record fields or claim RFC canonicalization.

| Logical value | JSON representation |
| --- | --- |
| null, Boolean, signed/unsigned integer, binary64, text | Corresponding JSON scalar |
| bytes | `{"$bytes":"<uppercase hexadecimal>"}` |
| none / some(value) | `[0]` / `[1,value]` |
| sequence | JSON array |
| map | Array of `[key,value]` pairs, preserving arbitrary key types and order |
| record | JSON object in adapter field order |
| enumeration | JSON string literal |
| variant | `["<alternative>", {<payload fields>}]` |

The tags above are backend representation, not Type IR or wire identities. A reader interprets them only when the
type adapter requests the corresponding logical kind.

`Bounded_Writer` owns fixed-capacity storage and exposes output only through `Copy_Output` into a caller buffer;
there is no unconstrained-string convenience result on the bounded path. `Allocating_Writer` uses
`Ada.Strings.Unbounded` explicitly and offers `Output`. Both writers are poisoned after a capacity, grammar, text, or
unsupported-value error and must be reset before reuse. A partial prefix is never reported as complete.

Strings and names must be valid UTF-8. Control characters, quotation marks, and reverse solidus are escaped. Other
valid UTF-8 bytes are preserved. Byte values use uppercase hexadecimal. Nonfinite binary64 is rejected before the
first output event; finite values, including signed zero, use Ada's target IEEE binary64 image and are tested as JSON
numbers.
