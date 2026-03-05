--  Safe Language Annotated SPARK Companion
--  Source commit: 468cf72332724b04b7c193b4d2a3b02f1584125d
--  Generated: 2026-03-02
--  Generator: spec2spark v0.1.0
--  Clauses: 2.8.1 (p126-p130), 2.8.2 (p131-p132), 2.8.3 (p133-p134),
--           2.8.4 (p136), 2.8.5 (p139-p139e), 2.3 (p94-p108),
--           4.2-4.3 (p12-p31a), 4.5 (p45-p52), 5.3 (p12-p31), 5.4 (p32-p40)
--  Assumptions:
--    - Implementation provides at least 64-bit intermediate evaluation
--    - Target hardware supports IEEE 754 non-trapping mode
--    - Static range analysis is sound
--    - Channel implementation correctly serializes access

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Safe_Model
  with Pure, Ghost
is

   ---------------------------------------------------------------------------
   --  Part 1: Range64 Model (D27 Rule 1 -- Wide Arithmetic)
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126:812b54a8
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p128:d2e83ca8
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.2.p15:1ab3314c
   ---------------------------------------------------------------------------

   type Range64 is record
      Lo : Long_Long_Integer;
      Hi : Long_Long_Integer;
   end record;
   --  Represents a closed interval [Lo .. Hi] in 64-bit signed integer space.
   --  Used to model the result of static range analysis on wide intermediates.

   function Is_Valid_Range (R : Range64) return Boolean is
     (R.Lo <= R.Hi)
   with Ghost;
   --  A range is valid iff the lower bound does not exceed the upper bound.

   function Contains (R : Range64; V : Long_Long_Integer) return Boolean is
     (V >= R.Lo and then V <= R.Hi)
   with Ghost,
        Pre => Is_Valid_Range (R);
   --  Returns True iff V is within the closed interval [R.Lo .. R.Hi].

   function Subset (A, B : Range64) return Boolean is
     (A.Lo >= B.Lo and then A.Hi <= B.Hi)
   with Ghost,
        Pre => Is_Valid_Range (A) and then Is_Valid_Range (B);
   --  Returns True iff every value in A is also in B.

   function Intersect (A, B : Range64) return Range64 is
     (Range64'(Lo => Long_Long_Integer'Max (A.Lo, B.Lo),
               Hi => Long_Long_Integer'Min (A.Hi, B.Hi)))
   with Ghost,
        Pre => Is_Valid_Range (A)
               and then Is_Valid_Range (B)
               and then Long_Long_Integer'Max (A.Lo, B.Lo)
                        <= Long_Long_Integer'Min (A.Hi, B.Hi);
   --  Returns the intersection of two overlapping ranges.

   function Widen (A, B : Range64) return Range64 is
     (Range64'(Lo => Long_Long_Integer'Min (A.Lo, B.Lo),
               Hi => Long_Long_Integer'Max (A.Hi, B.Hi)))
   with Ghost,
        Pre => Is_Valid_Range (A) and then Is_Valid_Range (B);
   --  Returns the smallest range containing both A and B.

   function Excludes_Zero (R : Range64) return Boolean is
     (R.Hi < 0 or else R.Lo > 0)
   with Ghost,
        Pre => Is_Valid_Range (R);
   --  Returns True iff zero is not contained in R.
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.3.p133:0610d951

   --  Common range constants
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p128:d2e83ca8

   Range_Int8  : constant Range64 := (Lo => -128, Hi => 127);
   Range_Uint8 : constant Range64 := (Lo => 0, Hi => 255);

   Range_Int16  : constant Range64 := (Lo => -32_768, Hi => 32_767);
   Range_Uint16 : constant Range64 := (Lo => 0, Hi => 65_535);

   Range_Int32  : constant Range64 :=
     (Lo => -2_147_483_648, Hi => 2_147_483_647);
   Range_Uint32 : constant Range64 :=
     (Lo => 0, Hi => 4_294_967_295);

   Range_Int64  : constant Range64 :=
     (Lo => Long_Long_Integer'First, Hi => Long_Long_Integer'Last);

   Range_Positive : constant Range64 :=
     (Lo => 1, Hi => Long_Long_Integer'Last);

   Range_Natural : constant Range64 :=
     (Lo => 0, Hi => Long_Long_Integer'Last);

   ---------------------------------------------------------------------------
   --  Part 2: Channel FIFO Ghost Model (Sections 4.2 - 4.3)
   --
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p15:b5b29b0e
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p20:8aa1a21e
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p27:ef0ce6bd
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p28:ea6bd13c
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p31:a7297e97
   ---------------------------------------------------------------------------

   --  We model a bounded FIFO queue abstractly using a length and capacity.
   --  In a full ghost model, we would track the sequence of elements; here
   --  we capture the essential capacity invariant for proof obligations.
   --
   --  Note: SPARK disallows generics. We model the queue state abstractly
   --  with Natural counters, parameterised by capacity at construction.

   type Channel_State is record
      Length   : Natural;
      Capacity : Natural;
   end record;
   --  Ghost model of a bounded FIFO channel.
   --  Invariant: Length <= Capacity and Capacity >= 1.

   function Is_Valid_Channel (S : Channel_State) return Boolean is
     (S.Capacity >= 1 and then S.Length <= S.Capacity)
   with Ghost;

   function Len (S : Channel_State) return Natural is
     (S.Length)
   with Ghost,
        Pre => Is_Valid_Channel (S);

   function Is_Empty (S : Channel_State) return Boolean is
     (S.Length = 0)
   with Ghost,
        Pre => Is_Valid_Channel (S);

   function Is_Full (S : Channel_State) return Boolean is
     (S.Length = S.Capacity)
   with Ghost,
        Pre => Is_Valid_Channel (S);

   function Cap (S : Channel_State) return Natural is
     (S.Capacity)
   with Ghost,
        Pre => Is_Valid_Channel (S);

   function After_Append (S : Channel_State) return Channel_State is
     (Channel_State'(Length   => S.Length + 1,
                     Capacity => S.Capacity))
   with Ghost,
        Pre => Is_Valid_Channel (S) and then not Is_Full (S),
        Post => Is_Valid_Channel (After_Append'Result)
                and then Len (After_Append'Result) = Len (S) + 1;
   --  Ghost model of state after enqueueing one element.

   function After_Remove (S : Channel_State) return Channel_State is
     (Channel_State'(Length   => S.Length - 1,
                     Capacity => S.Capacity))
   with Ghost,
        Pre => Is_Valid_Channel (S) and then not Is_Empty (S),
        Post => Is_Valid_Channel (After_Remove'Result)
                and then Len (After_Remove'Result) = Len (S) - 1;
   --  Ghost model of state after dequeueing one element.

   function Make_Channel (Cap_Val : Positive) return Channel_State is
     (Channel_State'(Length => 0, Capacity => Cap_Val))
   with Ghost,
        Post => Is_Valid_Channel (Make_Channel'Result)
                and then Is_Empty (Make_Channel'Result);
   --  Create a fresh empty channel with given capacity.

   ---------------------------------------------------------------------------
   --  Part 3: Ownership State Model (Section 2.3)
   --
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96a:0eaf48aa
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96c:0b45de01
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.3.p99b:47108b45
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.4a.p102a:5bc5ab8b
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.4a.p102b:2ed757bd
   ---------------------------------------------------------------------------

   type Ownership_State is
     (Null_State, Owned, Moved, Borrowed, Observed);
   --  Abstract ownership state of an access value.
   --  Null_State: variable is null (no designated object).
   --  Owned: variable owns the designated object.
   --  Moved: ownership has been transferred away; use is illegal.
   --  Borrowed: temporarily lent for mutable access.
   --  Observed: temporarily lent for read-only access.

   function Is_Accessible (S : Ownership_State) return Boolean is
     (S = Owned or else S = Borrowed or else S = Observed)
   with Ghost;
   --  An access value may be read when owned, borrowed, or observed.
   --  Moved and Null_State are not accessible for dereference.
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.4.p136:fa5e94b7

   function Is_Dereferenceable (S : Ownership_State) return Boolean is
     (S = Owned or else S = Borrowed or else S = Observed)
   with Ghost;
   --  Alias for Is_Accessible, emphasising the dereference context.

   function Is_Movable (S : Ownership_State) return Boolean is
     (S = Owned)
   with Ghost;
   --  Only an owned value may be moved.
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.2.p96a:0eaf48aa

   function Is_Borrowable (S : Ownership_State) return Boolean is
     (S = Owned)
   with Ghost;
   --  Only an owned value may be borrowed.
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.3.p99b:47108b45

   function Is_Observable (S : Ownership_State) return Boolean is
     (S = Owned or else S = Observed)
   with Ghost;
   --  An owned or already-observed value may be observed (multiple observers).
   --  Clause: SAFE@468cf72:spec/02-restrictions.md#2.3.4a.p102a:5bc5ab8b

   function Is_Valid_Transition
     (From : Ownership_State;
      To   : Ownership_State) return Boolean
   is
     (case From is
        when Null_State =>
          To = Owned,
        when Owned =>
          To = Moved or else To = Borrowed
          or else To = Observed or else To = Null_State,
        when Moved =>
          To = Owned or else To = Null_State,
        when Borrowed =>
          To = Owned,
        when Observed =>
          To = Owned or else To = Observed)
   with Ghost;
   --  Valid ownership transitions:
   --    Null_State -> Owned (allocator or receive)
   --    Owned -> Moved (move), Borrowed (borrow), Observed (observe),
   --             Null_State (deallocation)
   --    Moved -> Owned (reassignment), Null_State (scope exit)
   --    Borrowed -> Owned (borrow end)
   --    Observed -> Owned (observe end), Observed (additional observer)

   ---------------------------------------------------------------------------
   --  Part 4: Task-Variable Ownership Model (Section 4.5)
   --
   --  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.5.p45:8bdd0c99
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.4.1.p32:90d4f527
   --  Clause: SAFE@468cf72:spec/05-assurance.md#5.4.1.p33:0fc25399
   ---------------------------------------------------------------------------

   --  Model a mapping from variable IDs to task IDs.
   --  In the ghost model we use a fixed-size array indexed by variable ID.
   --  A task ID of 0 means "not owned by any task".

   Max_Variables : constant := 1024;
   Max_Tasks     : constant := 64;

   subtype Var_Id_Range  is Natural range 0 .. Max_Variables - 1;
   subtype Task_Id_Range is Natural range 0 .. Max_Tasks;
   --  Task_Id_Range includes 0 as "no owner".

   No_Task : constant Task_Id_Range := 0;

   type Task_Var_Map is array (Var_Id_Range) of Task_Id_Range;
   --  Maps each variable to the ID of the task that owns it.
   --  No_Task (0) means the variable is not accessed by any task.

   function Exclusive_Owner
     (Var_Id : Var_Id_Range;
      Map    : Task_Var_Map) return Boolean
   is
     (Map (Var_Id) /= No_Task)
   with Ghost;
   --  Returns True iff Var_Id is assigned to exactly one task.
   --  The single-owner invariant is: for every Var_Id, at most one
   --  task ID appears. This is guaranteed by construction (the map
   --  stores a single value per key).

   function Is_Unowned
     (Var_Id : Var_Id_Range;
      Map    : Task_Var_Map) return Boolean
   is
     (Map (Var_Id) = No_Task)
   with Ghost;
   --  Returns True iff the variable is not owned by any task.

   function Owner_Of
     (Var_Id : Var_Id_Range;
      Map    : Task_Var_Map) return Task_Id_Range
   is
     (Map (Var_Id))
   with Ghost;
   --  Returns the task ID of the owner, or No_Task if unowned.

   function Assign_Owner
     (Var_Id  : Var_Id_Range;
      Task_Id : Task_Id_Range;
      Map     : Task_Var_Map) return Task_Var_Map
   with Ghost,
        Pre  => Map (Var_Id) = No_Task or else Map (Var_Id) = Task_Id,
        Post => Assign_Owner'Result (Var_Id) = Task_Id
                and then (for all V in Var_Id_Range =>
                            (if V /= Var_Id
                             then Assign_Owner'Result (V) = Map (V)));
   --  Assign Var_Id to Task_Id. Precondition ensures the variable is
   --  either unowned or already owned by the same task (idempotent).

   function No_Shared_Variables (Map : Task_Var_Map) return Boolean
   with Ghost;
   --  Returns True iff no variable is accessed by more than one task.
   --  Since the map stores a single task ID per variable, this invariant
   --  is satisfied by construction. This function exists as a proof anchor.

end Safe_Model;
