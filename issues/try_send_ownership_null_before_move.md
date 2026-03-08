# Test try_send_ownership.safe Receiver task violates null-before-move rule (§97a)

## Summary

The `Receiver` task in `tests/concurrency/try_send_ownership.safe` (lines 49–61)
declares `Item` outside the loop body but `receive`s into it on every iteration.
On the second iteration, `Item` is non-null from the previous `receive`, violating
the null-before-move legality rule (§2.3.2, paragraph 97a).

The test is marked `Expected: ACCEPT`, but by the spec's own rules it should be
rejected.

## Spec references

**§2.3.2, paragraph 97a (Null-before-move legality rule):**

> The target of any move into a pool-specific owning access variable — whether by
> assignment, `receive`, or `try_receive` — shall be provably null at the point of
> the move. [...] A conforming implementation shall reject any move into a variable
> that is not provably null at that program point.

**§2.3.2, paragraph 97c (Conforming pattern for repeated receive):**

The spec provides an explicit nonconforming example that matches the `Receiver`
task's structure:

```ada
-- NONCONFORMING: second receive overwrites non-null Msg
Msg : Node_Ptr;
loop
    receive Ch, Msg;          -- rejected on second iteration:
                               -- Msg is non-null from previous receive
    Process(Msg);
end loop;
```

## Current code (nonconforming)

`tests/concurrency/try_send_ownership.safe`, lines 49–61:

```ada
task Receiver is
   Item : Payload_Ptr = null;
begin
   loop
      receive Data_Ch, Item;
      if Item != null then
         Item.all.Value = 0;  -- process
      end if;
      --  Item goes out of scope at end of loop iteration;
      --  auto-deallocation reclaims storage.
   end loop;
end Receiver;
```

`Item` is declared at line 50, outside the loop. On the second iteration of the
loop, `Item` is non-null (set by the first `receive`). The `receive` at line 53
is a move-in to a non-null variable — a violation of §97a. The comment on
lines 58–59 claims `Item` goes out of scope at end of loop iteration, but `Item`
is scoped to the task body, not the loop body.

## Conforming fix

Per §97c, move the declaration inside the loop body:

```ada
task Receiver is
begin
   loop
      Item : Payload_Ptr;         -- null by default each iteration
      receive Data_Ch, Item;
      if Item != null then
         Item.all.Value = 0;
      end if;
   end loop;                       -- Item goes out of scope; auto-deallocation
end Receiver;
```

## Impact

- **Test correctness:** The test should either be marked `Expected: REJECT` or
  fixed to use the conforming pattern.
- **Spec confidence:** This is the spec's own test suite contradicting a normative
  rule. If discovered by an implementer, it could create doubt about whether §97a
  is intended to apply to `receive` in task loops.
