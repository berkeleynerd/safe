--  Verified Emission Template: Dispatcher-Based Select Lowering
--
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.4.p33:7a94ab51
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.4.p39:1012f4db
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.4.p41:cdf6a558
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.4.p42:dce8ac38
--  Reference: compiler/translation_rules.md Section 5
--
--  Demonstrates the compiler emission pattern for select statement lowering:
--    1. Each channel arm becomes a Try_Receive call in declaration order
--    2. Arms are tested in priority order (declaration order per spec)
--    3. A package-scope readiness dispatcher is modeled as a latch with
--       Reset/Signal/Signal_Delay/Await operations
--    4. A bounded wake schedule abstracts the finite environment trace
--       used to prove the blocking loop's control flow
--
--  SPARK constraints and modeling compromises:
--    - Protected entry blocking and Ada.Real_Time timing events are not
--      directly provable in SPARK.  The dispatcher control flow is
--      abstracted to finite wake schedules: channel wakes and delay wakes.
--      This models the emitted latch/timed-handler structure without a
--      polling quantum or wall-clock faithfulness assumption.
--    - Bounded wake schedules replace the emitted unbounded blocking
--      loops so SPARK can prove termination. Loop exhaustion yields
--      default output (Result = Default_Element, Found/Timed_Out = False).
--    - Item := Default_Element on failure paths satisfies SPARK flow
--      analysis for out parameter initialization.
--
--  PO hooks exercised: Check_Channel_Not_Empty

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Select_Dispatcher
  with SPARK_Mode => On
is

   Max_Capacity : constant := 16;
   Max_Wake_Iterations : constant := 100;

   subtype Element_Type is Integer;
   Default_Element : constant Element_Type := 0;
   subtype Capacity_Range is Positive range 1 .. Max_Capacity;
   subtype Count_Range is Natural range 0 .. Max_Capacity;
   subtype Index_Range is Positive range 1 .. Max_Capacity;
   subtype Wake_Range is
     Positive range 1 .. Max_Wake_Iterations;

   type Buffer_Array is array (Index_Range) of Element_Type;

   --  Channel-only dispatcher wake schedule used by the no-delay select.
   type Channel_Wake_Schedule is array (Wake_Range) of Boolean;

   --  Combined dispatcher wake schedule for a select with delay arm.
   type Delay_Wake_Kind is (No_Wake, Channel_Wake, Delay_Wake);
   type Delay_Wake_Schedule is array (Wake_Range) of Delay_Wake_Kind;

   function Any_Delay_Wake
     (S : Delay_Wake_Schedule) return Boolean
   is (for some I in Wake_Range => S (I) = Delay_Wake);

   --  Channel record compatible with template_channel_fifo pattern.
   type Channel (Capacity : Capacity_Range) is record
      Buffer : Buffer_Array;
      Head   : Index_Range;
      Tail   : Index_Range;
      Count  : Count_Range;
   end record;

   --  Structural invariant.
   function Is_Valid (Ch : Channel) return Boolean is
     (Ch.Head <= Ch.Capacity
      and then Ch.Tail <= Ch.Capacity
      and then Ch.Count <= Ch.Capacity);

   function Is_Empty (Ch : Channel) return Boolean is
     (Ch.Count = 0);

   --  Dispatcher latch abstracting the emitted protected object.
   type Dispatcher is record
      Signaled      : Boolean;
      Delay_Expired : Boolean;
   end record;

   function Is_Idle (D : Dispatcher) return Boolean is
     (not D.Signaled and then not D.Delay_Expired);

   procedure Reset (D : out Dispatcher)
     with Post => Is_Idle (D);

   procedure Signal (D : in out Dispatcher)
     with Post => D.Signaled
                  and then D.Delay_Expired = D.Delay_Expired'Old;

   procedure Signal_Delay (D : in out Dispatcher)
     with Post => D.Delay_Expired
                  and then D.Signaled = D.Signaled'Old;

   procedure Await (D : in out Dispatcher; Timed_Out : out Boolean)
     with Pre  => D.Signaled or else D.Delay_Expired,
          Post => Is_Idle (D)
                  and then Timed_Out = D.Delay_Expired'Old;

   --  Non-blocking receive: attempts to dequeue one element.
   --  Success = True iff the channel was non-empty and an item was received.
   procedure Try_Receive
     (Ch      : in out Channel;
      Item    : out Element_Type;
      Success : out Boolean)
     with Pre  => Is_Valid (Ch),
          Post => Is_Valid (Ch)
                  and then Success = (Ch.Count'Old > 0)
                  and then (if Success then
                              Ch.Count = Ch.Count'Old - 1
                            else
                              Ch.Count = Ch.Count'Old);

   --  Two-arm select with delay arm under the dispatcher lowering.
   --  Arms tested in declaration order: Ch_A (Arm 1), Ch_B (Arm 2).
   --  When no arm is ready, the dispatcher is awaited. Channel wakes
   --  represent successful sends; delay wakes represent the one absolute
   --  deadline handler firing.
   procedure Select_With_Delay
     (Ch_A      : in out Channel;
      Ch_B      : in out Channel;
      Wakeups   : Delay_Wake_Schedule;
      Result    : out Element_Type;
      Timed_Out : out Boolean)
     with Pre  => Is_Valid (Ch_A) and then Is_Valid (Ch_B),
          Post =>
            Is_Valid (Ch_A) and then Is_Valid (Ch_B)
            and then
              (if Timed_Out then
                 Any_Delay_Wake (Wakeups)
                 and then Ch_A.Count'Old = 0
                 and then Ch_B.Count'Old = 0
                 and then Ch_A.Count = Ch_A.Count'Old
                 and then Ch_B.Count = Ch_B.Count'Old
               elsif Ch_A.Count'Old > 0 then
                 Ch_A.Count = Ch_A.Count'Old - 1
                 and then Ch_B.Count = Ch_B.Count'Old
               elsif Ch_A.Count'Old = 0 and then Ch_B.Count'Old > 0 then
                 Ch_A.Count = Ch_A.Count'Old
               else
                 Ch_A.Count = Ch_A.Count'Old
                 and then Ch_B.Count = Ch_B.Count'Old);

   --  Two-arm select without delay arm under the dispatcher lowering.
   --  Arms are tested in declaration order: Ch_A (Arm 1), Ch_B (Arm 2).
   --  Found = True iff an item was successfully received from either channel.
   procedure Select_No_Delay
     (Ch_A   : in out Channel;
      Ch_B   : in out Channel;
      Wakeups : Channel_Wake_Schedule;
      Result : out Element_Type;
      Found  : out Boolean)
     with Pre  => Is_Valid (Ch_A) and then Is_Valid (Ch_B),
          Post =>
            Is_Valid (Ch_A) and then Is_Valid (Ch_B)
            and then
              (if Ch_A.Count'Old > 0 then
                 Found
                 and then Ch_A.Count = Ch_A.Count'Old - 1
                 and then Ch_B.Count = Ch_B.Count'Old
               elsif Ch_A.Count'Old = 0 and then Ch_B.Count'Old > 0 then
                 Found
                 and then Ch_A.Count = Ch_A.Count'Old
               else
                 not Found
                 and then Ch_A.Count = Ch_A.Count'Old
                 and then Ch_B.Count = Ch_B.Count'Old);

end Template_Select_Dispatcher;
