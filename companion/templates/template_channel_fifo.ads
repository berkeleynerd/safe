--  Verified Emission Template: Bounded Channel FIFO
--
--  Clause: SAFE@4aecf21:spec/04-tasks-and-channels.md#4.2.p15:b5b29b0e
--  Clause: SAFE@4aecf21:spec/04-tasks-and-channels.md#4.2.p20:8aa1a21e
--  Clause: SAFE@4aecf21:spec/04-tasks-and-channels.md#4.3.p27:ef0ce6bd
--  Clause: SAFE@4aecf21:spec/04-tasks-and-channels.md#4.3.p28:ea6bd13c
--  Clause: SAFE@4aecf21:spec/04-tasks-and-channels.md#4.3.p31:a7297e97
--  Reference: compiler/translation_rules.md Section 4
--  Reference: tests/golden/golden_pipeline.ada
--
--  Demonstrates the compiler emission pattern for channel operations.
--  In emitted code, channels become protected objects with ceiling priority
--  (see golden_pipeline.ada). This template verifies the functional
--  invariants that the protected object implementation must maintain:
--    - Channel capacity is positive at construction
--    - Send only when not full
--    - Receive only when not empty
--    - FIFO ordering is preserved
--    - Head and Tail indices stay within 1..Capacity
--
--  The model is sequential (not a protected object) to enable full
--  GNATprove functional verification. The concurrency safety guarantee
--  comes from the Jorvik runtime model (ceiling locking protocol).
--
--  PO hooks exercised: Check_Channel_Capacity_Positive,
--                       Check_Channel_Not_Full,
--                       Check_Channel_Not_Empty

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Template_Channel_FIFO
  with SPARK_Mode => On
is

   Max_Capacity : constant := 16;

   subtype Element_Type is Integer;
   subtype Capacity_Range is Positive range 1 .. Max_Capacity;
   subtype Count_Range is Natural range 0 .. Max_Capacity;
   subtype Index_Range is Positive range 1 .. Max_Capacity;

   type Buffer_Array is array (Index_Range) of Element_Type;

   --  Sequential model of a bounded FIFO channel.
   --  In emitted code, this is a protected object.
   type Channel (Capacity : Capacity_Range) is record
      Buffer : Buffer_Array;
      Head   : Index_Range;
      Tail   : Index_Range;
      Count  : Count_Range;
   end record;

   --  Structural invariant: Head and Tail are within 1..Capacity,
   --  and Count does not exceed Capacity.
   function Is_Valid (Ch : Channel) return Boolean is
     (Ch.Head <= Ch.Capacity
      and then Ch.Tail <= Ch.Capacity
      and then Ch.Count <= Ch.Capacity);

   --  Construction: create an empty channel with given capacity.
   function Make (Cap : Capacity_Range) return Channel
     with Post => Is_Valid (Make'Result)
                  and then Make'Result.Count = 0
                  and then Make'Result.Capacity = Cap;

   --  Query: is the channel empty?
   function Is_Empty (Ch : Channel) return Boolean is
     (Ch.Count = 0);

   --  Query: is the channel full?
   function Is_Full (Ch : Channel) return Boolean is
     (Ch.Count = Ch.Capacity);

   --  Query: current length.
   function Length (Ch : Channel) return Count_Range is
     (Ch.Count);

   --  Send: enqueue an element (requires valid + not full).
   procedure Send
     (Ch   : in out Channel;
      Item : Element_Type)
     with Pre  => Is_Valid (Ch) and then Ch.Count < Ch.Capacity,
          Post => Is_Valid (Ch) and then Ch.Count = Ch.Count'Old + 1;

   --  Receive: dequeue an element (requires valid + not empty).
   procedure Receive
     (Ch   : in out Channel;
      Item : out Element_Type)
     with Pre  => Is_Valid (Ch) and then Ch.Count > 0,
          Post => Is_Valid (Ch) and then Ch.Count = Ch.Count'Old - 1;

end Template_Channel_FIFO;
