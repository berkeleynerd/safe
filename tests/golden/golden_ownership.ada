--  Golden output: Expected Ada/SPARK translation of ownership_move.safe
--  Source: tests/positive/ownership_move.safe
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96a:0eaf48aa
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96c:0b45de01
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p97a:8d0214d5
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.5.p104:d9f9b8d9
--
--  The Safe compiler translates ownership moves by:
--  1. Copying the access value to the target.
--  2. Setting the source to null.
--  3. Inserting a not-null assertion before each dereference.
--  4. Inserting Unchecked_Deallocation at scope exit for non-null owners.

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

with Ada.Unchecked_Deallocation;

package Ownership_Move
  with SPARK_Mode => On
is

   type Payload is record
      Value : Integer;
   end record;

   type Payload_Ptr is access Payload;

   procedure Transfer;

end Ownership_Move;

pragma SPARK_Mode (On);

package body Ownership_Move
  with SPARK_Mode => On
is

   procedure Free is new Ada.Unchecked_Deallocation
     (Object => Payload, Name => Payload_Ptr);

   procedure Transfer is
      Source : Payload_Ptr := new Payload'(Value => 42);
      Target : Payload_Ptr := null;
   begin
      --  Move: copy access value, null source.
      --  Precondition: Target is null (null-before-move rule).
      pragma Assert (Target = null);
      Target := Source;
      Source := null;

      --  Dereference Target: not-null assertion.
      pragma Assert (Target /= null);
      Target.all.Value := 100;

      --  Scope exit: auto-deallocation of non-null owned pointers.
      --  Source is null (moved), so no deallocation needed.
      --  Target is non-null, so deallocate in reverse declaration order.
      if Target /= null then
         Free (Target);
      end if;
      --  Source is already null; no action.
   end Transfer;

end Ownership_Move;
