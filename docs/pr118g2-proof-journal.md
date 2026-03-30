# PR11.8g.2 Proof Journal

## 2026-03-30

### Current branch state

- Branch: `codex/pr118g2-shared-runtime-io-seam`
- Draft PR: `#160`
- Green locally:
  - `alr build`
  - `python3 scripts/run_tests.py` -> `428 passed, 0 failed`
  - `python3 scripts/run_samples.py` -> `18 passed, 0 failed`
- Remaining blocker: full `python3 scripts/run_proofs.py`

### Reproduced proof blocker

- Fixture: `tests/build/pr118d_bounded_string_build.safe`
- Reproduced locally with:
  - single fixture
  - single prover: `z3`
  - single-threaded GNATprove settings
  - both pinned and unpinned CPU runs
- Result: same bad VC shape both ways
  - `pr118d_bounded_string_build-T-defqtvc.smt2`
- Conclusion: this is not primarily scheduler noise or proof-process parallel non-determinism.

### Narrowing results

- `gnatprove --limit-subp=safe_bounded_strings.adb:33` completes quickly.
  - Interpretation: the shared bounded-string `Slice` helper body itself is not the direct blocker.
- `gnatprove --limit-line=pr118d_bounded_string_build.ads:16` hangs in the same proof phase.
  - Line 16 is:
    - `prefix : Safe_Bounded_String_5_Type := Safe_Bounded_String_5.To_Bounded (Safe_Bounded_String_5.Slice (name, 1, 2));`

### Current working hypothesis

- The problematic proof surface is the composition:
  - bounded-target initialization through `To_Bounded (Slice (...))`
- The next implementation step is to avoid that composition when the source is already a bounded string of the same capacity, by emitting a direct bounded-string slice helper instead of routing through an intermediate `String`.

### Fresh narrowing after `Slice_Bounded`

- Emitted `pr118d_bounded_string_build.ads` now uses:
  - `prefix : Safe_Bounded_String_5_Type := Safe_Bounded_String_5.Slice_Bounded (name, 1, 2);`
- `gnatprove --limit-line=pr118d_bounded_string_build.adb:11` now completes and proves.
  - Interpretation: the package-body string comparisons are not the current blocker.
- `gnatprove --limit-line=pr118d_bounded_string_build.ads:16` no longer hangs; it fails with one concrete unproved contract check:
  - `precondition might fail, cannot prove High <= Length (Value)`
  - on `Safe_Bounded_String_5.Slice_Bounded (name, 1, 2)`
- Interpretation:
  - the fresh blocker is a missing visible fact about `To_Bounded`, not the `Slice_Bounded` body itself
  - GNATprove does not know that:
    - `Length (Safe_Bounded_String_5.To_Bounded ("hello")) = 5`

### Current contract fix under test

- Strengthen the shared bounded-string spec with the minimum length facts needed by callers:
  - `To_Bounded` postcondition states result length matches source string length
  - `To_String` postcondition states result string length matches bounded-string length
  - `Element` postcondition states the returned string has length `1`
- Rationale:
  - fixes the concrete `Slice_Bounded` precondition failure on package elaboration
  - should also help the `for ... of string` path, which constructs `string (1)` loop items from bounded-string indexing

### Results after contract patch

- `gnatprove --limit-line=pr118d_bounded_string_build.ads:16` now proves.
  - The earlier `High <= Length (Value)` failure is gone.
- `gnatprove --limit-line=pr118d1_for_of_string_build.adb:39` proves.
  - `Safe_Bounded_String_1.To_Bounded (Safe_For_Of_Snapshot_2 (...))` is now accepted with the shared spec surface.
- `gnatprove --limit-line=pr118d1_for_of_string_build.adb:34` proves.
  - The bounded-string `To_String (short)` snapshot itself is not the current blocker.

### Updated working hypothesis

- The bounded-string seam problem was primarily missing visible length facts in the shared `Safe_Bounded_Strings` spec, not a bad body implementation.
- Next step:
  - rerun the full emitted fixtures for:
    - `pr118d_bounded_string_build.safe`
    - `pr118d_bounded_string_field_build.safe`
    - `pr118d_bounded_string_index_build.safe`
    - `pr118d1_for_of_string_build.safe`
  - if those stay green, widen back out to the full `PR11.8g.2` checkpoint and then full `run_proofs.py`

### Full-fixture follow-up

- In isolated full-fixture `prove` runs, the hot VC moved from the old package-spec initializer to the shared helper proof surface.
- `--limit-subp=safe_bounded_strings.adb:5` (`To_Bounded`) proves quickly.
- `--limit-subp=safe_bounded_strings.adb:15` (`To_String`) also proves quickly in isolation.
- But the full emitted `pr118d_bounded_string_build` package still spends its time in `Safe_Bounded_String_*.__to_string` when proving the whole unit at once.
- Current experiment:
  - keep the `To_Bounded` and `Element` visible length facts
  - drop the `To_String` length postcondition, since the narrowed `for ... of string` checks do not appear to need it and it is the current highest-probability source of the remaining proof blow-up

### Result after dropping `To_String` post

- `gnatprove --limit-line=pr118d1_for_of_string_build.adb:34` still proves without the `To_String` length postcondition.
- Conclusion:
  - the bounded-string snapshot path does not currently need a visible `To_String` length fact
  - keeping `To_Bounded` and `Element` contracts while dropping `To_String` is the better cost/benefit point so far

### Current structural simplification

- Moved these tiny bounded-string helpers from package-body implementations to private-part expression-function completions:
  - `Length`
  - `To_String`
  - `Element`
  - `Slice`
- Rationale:
  - the remaining full-fixture cost was cycling across instantiated helper bodies even though each helper proved quickly in isolation
  - expression-function completion should let GNATprove inline these helpers instead of re-proving multiple nearly identical instantiated bodies
- `To_Bounded` and `Slice_Bounded` stay as ordinary body-defined functions for now.

### Result after helper inlining

- Full direct `z3` prove of emitted `pr118d_bounded_string_build` now completes successfully.
- The previous aggregate-cost blow-up across instantiated helper bodies is gone.
- Current status after this change:
  - package-spec initializer proof is green
  - bounded-string helper bodies still prove
  - full emitted bounded-string fixture proves end-to-end under direct `gnatprove`

### Bounded-string subset reclosed

- Emitted-fixture batch with `z3` only is now green for:
  - `pr118d_bounded_string_build.safe`
  - `pr118d_bounded_string_field_build.safe`
  - `pr118d_bounded_string_index_build.safe`
  - `pr118d1_for_of_string_build.safe`
- The same four fixtures are also green under the normal `cvc5,z3,altergo` prove switches.
- Conclusion:
  - the bounded-string shared-runtime proof regression is locally reclosed
  - this seam is no longer the frontmost `PR11.8g.2` blocker

### New front of the queue

- The next targeted `PR11.8g.2` batch stalled immediately on:
  - `tests/build/pr118d_fixed_to_growable_build.safe`
- It did not reach the heap-backed channel fixtures before being stopped.
- So after the bounded-string fix, the next proof investigation should shift to the `fixed_to_growable` path before widening again to the full checkpoint.

### `pr118d_fixed_to_growable_build.safe` reclosed

- Shared-array runtime changes that closed the fixture:
  - `Safe_Array_RT.From_Array` now exposes both:
    - result length
    - per-element preservation
  - `Safe_Array_RT.Clone` now exposes result-length preservation
  - `Safe_Array_RT.Copy` now exposes target-length preservation
  - `Safe_Array_RT.Free` now exposes zero length after cleanup
- Emitter change that mattered:
  - access-parameter length preconditions are now synthesized for parameter-root indexed/sliced growable arrays, strings, and bounded strings
- Result:
  - `tests/build/pr118d_fixed_to_growable_build.safe` proves in isolation under both:
    - `z3`
    - the normal `cvc5,z3,altergo` mix
- Cleanup folded into the same step:
  - removed the dead tautological runtime drift check from `scripts/_lib/pr09_emit.py`

### `pr118g_growable_channel_build.safe` investigation

- First heap-backed channel blocker after `fixed_to_growable`:
  - `tests/build/pr118g_growable_channel_build.safe`

- Preserved probe directories:
  - `/tmp/pr118g_grow_prove4_eJ7Pki/fixture/ada`
  - `/tmp/pr118g_grow_prove5_aVg6ij/fixture/ada`
  - `/tmp/pr118g_grow_prove6_Bmf1ki/fixture/ada`
  - `/tmp/pr118g_grow_check5_ben_k6mw/fixture/ada`
  - `/tmp/pr118g_grow_check10_mj65dfkp/fixture/ada`

#### Dead end: package-level ghost wrapper model

- Attempt:
  - add package ghost `*_Model_Length`
  - route single-slot direct growable/string channels through staged send/receive wrappers
  - carry send length through wrapper postconditions
- Result:
  - first version failed flow because:
    - the ghost state was missing from `Initializes`
    - GNATprove emitted `is set by` warnings on the receive wrapper call
  - after patching those, flow went green
  - prove still failed inside the wrapper contracts:
    - could not prove `Value_Length = *_Model_Length`
    - could not prove `Length (Value) = Value_Length`
- Conclusion:
  - the wrapper ghost model moved the problem but did not close it

#### Dead end: direct receive plus recomputed actual length

- Attempt:
  - remove the receive/send wrappers again
  - call protected `Send` / `Receive` / `Try_*` directly
  - recompute the staged value length after receive outside the protected body
- Result:
  - flow became clean after a narrow generated `is set by` suppression around the direct receive call
  - prove improved:
    - staged-length and target-length assertions both proved
    - the final `values_RT.Element (received, 1)` precondition was still unproved
- Interpretation:
  - recomputing actual length outside the protected body is useful and should likely be kept
  - but it does not by itself carry the send-side non-empty fact across the channel

#### Dead end: `Stored_Length` over `Count` and `Lengths`

- Attempt:
  - add a single-slot protected `Stored_Length` helper
  - add postconditions on protected `Send` / `Receive` using that helper
- Result:
  - compiled and flowed cleanly
  - prove still failed on the `Send` / `Receive` postconditions
  - GNATprove explicitly suggested either:
    - a postcondition on `Stored_Length`
    - or turning it into an expression function
- Follow-up attempt:
  - tried to complete `Stored_Length` as an expression function in the protected type private part
- Result:
  - Ada rejected that shape because protected components cannot be referenced there before the end of the declaration
- Conclusion:
  - the bounded-string-style expression-function trick does not transfer directly to protected components

#### Current in-tree attempt

- Current shape:
  - keep the direct protected call path
  - recompute actual received length outside the protected body
  - add a dedicated single-slot scalar `Stored_Length_Value`
  - `Stored_Length` now returns that scalar, not `Lengths (Head)`
  - protected `Send` / `Receive` still carry numeric postconditions via `Stored_Length`
- Current result:
  - flow is green for `tests/build/pr118g_growable_channel_build.safe`
  - prove still fails in the same three places:
    - final `values_RT.Element (received, 1)` precondition
    - `Send` postcondition `Stored_Length = Value_Length`
    - `Receive` postcondition `Value_Length = Stored_Length'Old`

### Current conclusion

- The first heap-backed channel blocker is narrower now, but it is not closed.
- The real unsolved issue is:
  - making the single-slot numeric send-to-receive length fact proof-visible enough for GNATprove to use it modularly
- The next step should avoid more wrapper churn unless it directly addresses that modular numeric fact.

### Step 1 result: protected-body expression function is legal and helps

- I verified separately that Ada accepts an expression-function completion in a protected body.
- I then changed the single-slot helper to:
  - `function Stored_Length return Natural is (Stored_Length_Value);`
- Result:
  - isolated `Send` and `Receive` postconditions now prove
  - this is a real improvement over the earlier body-defined helper
- But:
  - the downstream caller obligation at the final `values_RT.Element (received, 1)` precondition still did not close
- Conclusion:
  - the protected-side fact hand-off is better
  - but the caller is still missing a usable positivity/non-empty fact

### Step 2 result: boolean fallback still hits a tool bug

- I retried the weaker `Stored_Nonempty` approach after the expression-function win.
- Result:
  - GNATprove again tripped the same internal failure (`Constraint_Error bad input for 'Value: "0GG"`)
- Conclusion:
  - the boolean hand-off remains non-viable on the current toolchain

### Step 3 result: receive-site assumption alone is too weak

- I removed the abandoned wrapper layer again and kept direct protected calls.
- I added the narrowest receive-side bridge in emitted receive paths:
  - after direct `Receive` / successful `Try_Receive`
  - `pragma Assume (actual_length = returned_length)`
- Result:
  - the emitted fixture compiles and the direct receive call itself proves
  - the post-assignment equality assertion also proves
  - but the final `values_RT.Element (received, 1)` precondition is still unproved
- Interpretation:
  - the remaining missing fact is not “actual length equals returned length”
  - it is “the returned length is positive / matches the previously sent non-empty length”

### Stronger trust-bridge experiments

- I tried the next stronger hand-off in a preserved emitted probe:
  - capture `data_ch.Stored_Length` before receive
  - relate returned length to that captured scalar
- Result:
  - GNATprove still could not prove either:
    - returned length equals the captured stored length
    - captured stored length is positive
- I then tried a send-side trust bridge in the probe:
  - assume channel stored length equals the sent length immediately after `Send`
- Result:
  - referencing `data_ch.Stored_Length` directly inside a `pragma Assume` fails SPARK flow with:
    - `call to a volatile function in interfering context is not allowed in SPARK`
- A follow-up probe that combined the stronger send-side bridge with local debug assertions also triggered the existing GNATprove internal failure:
  - `Constraint_Error bad input for 'Value: "0GG"`

### Current frontier

- What is now established:
  - protected-body expression-function transparency is worth keeping
  - receive-side `actual_length = returned_length` assumptions are legal
  - those assumptions alone do not close the final caller precondition
  - send-side trust bridges that mention the protected function directly inside `pragma Assume` are not legal in SPARK
- So the frontmost blocker is now narrower still:
  - finding a legal way to carry the previously sent positive length across the single-slot protected channel boundary without reintroducing wrapper churn or hitting the GNATprove bug

### Rejected: package-level sent-length mirror

- Rejected idea:
  - add a package-level scalar like `data_ch_Sent_Length : Natural := 0;`
  - write it after `Send`
  - then use it in receive-side `pragma Assume` facts
- Reason for rejection:
  - the mirror is outside the protected object, so it is not synchronized with the actual channel state
  - `capacity 1` does not make that safe
- Concrete bad interleaving:
  - task A completes `data_ch.Send (...)`
  - task B immediately executes `data_ch.Receive (...)` and empties the channel
  - task A then executes `data_ch_Sent_Length := Sent_Length`
  - the package scalar now says the channel holds a positive-length value even though the channel is empty
- Consequence:
  - the mirror can drift from the protected state
  - any receive-side assumption like `Recv_Length = data_ch_Sent_Length` would be trusting a caller-maintained mirror, not the protected transition itself
- Additional reason to reject:
  - it introduces a new shared mutable package variable and therefore new concurrency/global proof obligations instead of narrowing the seam
- Conclusion:
  - do not pursue caller-side package mirrors for channel length facts
  - any trusted bridge must stay tied to the protected receive/send event itself or another hand-off that is atomic with the protected operation

### Rejected: receive-side-only positivity assume

- Rejected idea:
  - strengthen the existing receive-side bridge from:
    - `pragma Assume (actual_length = returned_length)`
  - to:
    - `pragma Assume (returned_length > 0 and then actual_length = returned_length)`
- Reason for rejection:
  - a successful receive means only that the channel held a value
  - it does **not** mean the value length was positive
- Counterexample:
  - the language permits empty strings and empty growable arrays
  - a sender can legally enqueue `""` or `[]`
  - the channel is non-empty (`Count > 0`) but the stored `Value_Length` is still `0`
- Consequence:
  - `Recv_Length > 0` would be an unsound assumption for the admitted direct string/growable channel surface
  - it would “fix” the current fixture only by overclaiming a property that is false for valid programs
- Conclusion:
  - keep the receive-side equality bridge as the only currently legal receive-local assumption
  - the missing fact is specifically the send-to-receive preservation of the original length, not non-emptiness of the receive event itself

### Rejected: synthesized receive-site defensive guard

- Rejected idea:
  - emit a program-specific Ada guard at the receive site, for example:
    - `if values_RT.Length (received) >= 1 then ... end if;`
  - so the emitted Ada defensively checks the condition that the Safe source relied on implicitly
- Reason for rejection:
  - this is not semantics-preserving at the compiler level
  - if the condition is false, the emitted Ada would silently skip work that the Safe source did not guard
- Why this is not acceptable here:
  - the whole issue is that the compiler currently lacks a discharged proof of the fact
  - synthesizing control flow to satisfy the prover would turn a proof gap into a runtime behavior change
- Even for the current fixture:
  - the branch may be dead in the intended execution
  - but the compiler cannot justify changing emitted semantics based on that unproved assumption
- Conclusion:
  - do not pursue ad hoc emitted receive-site guards as a proof workaround
  - if a guard is ever appropriate, it must come from source-level Safe syntax or an explicit source assertion, not from compiler-injected control flow

### Clarification: internal move semantics are already in place

- Useful observation:
  - the current heap-backed channel lowering already uses ownership-transfer style moves internally
  - this is **not** a remaining “copy vs move inside the protected body” problem
- Current emitted shape already does the structurally right thing:
  - clone the user value at the send site
  - move that staged clone into the protected buffer
  - reset the staged local
  - move from the protected buffer into the receive-side staged local
  - free the old user target and move the staged value into it
- So at the emitted Ada level:
  - the protected body is already heap-op free
  - the staged channel path already behaves like a single-owner move chain
  - the Safe-level value-copy semantics are preserved because the user source is cloned before send
- Conclusion:
  - the open blocker is narrower than “use ownership transfer internally”
  - that part is already done
  - the remaining unsolved seam is the proof-visible hand-off of the length fact attached to the moved staged value, especially across the `Value_Length` scalar and the protected boundary

### Final PR11.8g.2 channel closure path

- The direct scalar channel seam was closed with the following emitted shape:
  - direct sequential single-slot string/growable channels now emit synchronized package-level model scalars:
    - `<channel>_Model_Has_Value : Boolean := False;`
    - `<channel>_Model_Length : Natural := 0;`
  - those scalars are updated **inside** the protected operations, alongside the buffer move/reset logic
  - the direct scalar protected API keeps `Value_Length` formals
  - the old `Stored_Length` / `Stored_Length_Value` helper path is removed for this direct scalar case
  - the narrow receive-side bridge remains:
    - `pragma Assume (actual_length = returned_length)`
- Important honesty note:
  - this is **not** the pure Ghost/no-assumption endpoint that we explored
  - the final direct scalar closure still relies on the receive-side equality `pragma Assume`
  - what changed is that the protected/body-side handoff is now simple enough that the remaining trusted fact is narrow and stable
- What this closed:
  - `pr118g_string_channel_build.safe`
  - `pr118g_growable_channel_build.safe`
  - `pr118g_try_string_channel_build.safe`
  - the wider heap-backed channel batch also reclosed:
    - `pr118g_tuple_string_channel_build.safe`
    - `pr118g_record_string_channel_build.safe`

### Full-lane follow-up outside the channel seam

- Once the channel checkpoint was green, the full `run_proofs.py` lane exposed one older emitted-surface failure in `PR11.8a`:
  - `tests/positive/pr113_discriminant_constraints.safe`
- Root cause:
  - package-level non-constant object declarations without `=` were not being marked for implicit default initialization
  - the fix could not be a blanket “always emit a default initializer,” because that immediately reopened `pr118d_bounded_string_field_build.safe` with a no-effect initialization warning on a self-defaulting record
- Final fix:
  - package-level object declarations now opt into implicit default initialization at parse time
  - the emitter only materializes an explicit default initializer when the resolved type **needs** one to avoid uninitialized state
  - discriminated record/subtype default values now render as valid qualified aggregates instead of falling back to invalid `'First` forms
- Concrete effect:
  - `pr113_discriminant_constraints.safe` reclosed in isolation
  - `pr118d_bounded_string_field_build.safe` stayed green after narrowing the emitter-side default-init rule

### Current verified state

- `cd compiler_impl && alr build` is green
- `python3 scripts/run_tests.py` is green:
  - `434 passed, 0 failed`
- `python3 scripts/run_samples.py` is green:
  - `18 passed, 0 failed`
- full proof lane is green:
  - `python3 scripts/run_proofs.py`
  - `120 proved, 0 failed`
