--  Verified Emission Template: Borrow and Observe Ownership Patterns
--
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.3.p99b:47108b45
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.4a.p102a:5bc5ab8b
--  Reference: compiler/translation_rules.md Section 7
--
--  Demonstrates the compiler emission patterns for borrow (exclusive
--  mutable temporary access) and observe (shared read-only temporary
--  access) ownership transitions:
--    1. Borrow: lender must be Owned; lender is frozen (Borrowed state)
--       during the borrow scope, then restored to Owned.
--    2. Observe: lender must be Owned or Observed; lender enters
--       Observed state, then is restored when the observer ends.
--    3. Multiple observers: a second observe on an already-Observed
--       lender exercises the Observed->Observed transition.
--
--  SPARK restriction: access types and ghost types from Safe_Model
--  cannot appear in non-ghost record fields. We model ownership state
--  using Boolean flags and map to Safe_Model.Ownership_State only in
--  ghost PO hook calls.
--
--  PO hooks exercised: Check_Borrow_Exclusive, Check_Observe_Shared

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Borrow_Observe
  with SPARK_Mode => On
is

   --  Extended pointer model with borrow/observe flags.
   --  Null:     Is_Null, not Is_Moved     -> Null_State
   --  Owned:    not Is_Null, not Is_Moved -> Owned
   --  Moved:    Is_Null, Is_Moved         -> Moved
   --  Borrowed: not Is_Null, Is_Borrowed  -> Borrowed
   --  Observed: not Is_Null, Is_Observed  -> Observed
   type Ptr_Model is record
      Is_Null     : Boolean;
      Is_Moved    : Boolean;
      Is_Borrowed : Boolean;
      Is_Observed : Boolean;
      Value       : Integer;
   end record;

   --  State consistency: flags correspond to exactly one of the five
   --  ownership states (Owned, Null, Moved, Borrowed, Observed).
   --  Rejects illegal combinations such as Borrowed+Observed or
   --  Moved without Null.
   function Is_Consistent (P : Ptr_Model) return Boolean is
     (not (P.Is_Borrowed and then P.Is_Observed)
      and then not (P.Is_Borrowed and then P.Is_Null)
      and then not (P.Is_Observed and then P.Is_Null)
      and then not (P.Is_Borrowed and then P.Is_Moved)
      and then not (P.Is_Observed and then P.Is_Moved)
      and then (if P.Is_Moved then P.Is_Null));

   --  Owned: not null, not moved, not borrowed, not observed.
   function Is_Owned (P : Ptr_Model) return Boolean is
     (not P.Is_Null
      and then not P.Is_Moved
      and then not P.Is_Borrowed
      and then not P.Is_Observed);

   --  Pattern: Exclusive borrow scope.
   --  Freeze lender, modify through borrower, restore.
   procedure Borrow_And_Modify
     (Lender    : in out Ptr_Model;
      New_Value : Integer;
      Result    : out Integer)
     with Pre  => Is_Owned (Lender),
          Post => Is_Owned (Lender)
                  and then Lender.Value = New_Value
                  and then Result = New_Value;

   --  Pattern: Observe scope.
   --  Read through observer, restore. Value unchanged.
   procedure Observe_And_Read
     (Lender : in out Ptr_Model;
      Result : out Integer)
     with Pre  => Is_Owned (Lender),
          Post => Is_Owned (Lender)
                  and then Lender.Value = Lender.Value'Old
                  and then Result = Lender.Value;

   --  Pattern: Nested observe scopes (two observers on same lender).
   --  Exercises the Observed -> Observed transition in Check_Observe_Shared.
   procedure Two_Observers
     (Lender : in out Ptr_Model;
      R1     : out Integer;
      R2     : out Integer)
     with Pre  => Is_Owned (Lender),
          Post => Is_Owned (Lender)
                  and then Lender.Value = Lender.Value'Old
                  and then R1 = Lender.Value
                  and then R2 = Lender.Value;

end Template_Borrow_Observe;
