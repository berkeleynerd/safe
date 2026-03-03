--  Verified Emission Template: Bounded Channel FIFO
--  See template_channel_fifo.ads for clause references.

pragma SPARK_Mode (On);

with Safe_PO; use Safe_PO;

package body Template_Channel_FIFO
  with SPARK_Mode => On
is

   -------------------------------------------------------------------
   --  Construction: create an empty channel
   --
   --  Emission pattern from translation_rules.md Section 4:
   --    ch : Channel(T, N) -> protected object with capacity N
   --  The compiler emits Check_Channel_Capacity_Positive at construction.
   -------------------------------------------------------------------
   function Make (Cap : Capacity_Range) return Channel is
   begin
      --  PO hook: verify capacity is positive.
      Check_Channel_Capacity_Positive (Cap);

      return Channel'(Capacity => Cap,
                      Buffer   => [others => 0],
                      Head     => 1,
                      Tail     => 1,
                      Count    => 0);
   end Make;

   -------------------------------------------------------------------
   --  Send: enqueue an element
   --
   --  Emission pattern:
   --    ch.send(item) -> protected entry call with barrier (Count < Cap)
   --  The compiler emits Check_Channel_Not_Full before the entry call.
   --  In the protected object, the barrier blocks until space is available.
   -------------------------------------------------------------------
   procedure Send
     (Ch   : in out Channel;
      Item : Element_Type)
   is
   begin
      --  PO hook: verify channel is not full.
      Check_Channel_Not_Full (Ch.Count, Ch.Capacity);

      --  Enqueue: write element at Tail, advance Tail circularly.
      Ch.Buffer (Ch.Tail) := Item;
      if Ch.Tail = Ch.Capacity then
         Ch.Tail := 1;
      else
         Ch.Tail := Ch.Tail + 1;
      end if;
      Ch.Count := Ch.Count + 1;
   end Send;

   -------------------------------------------------------------------
   --  Receive: dequeue an element
   --
   --  Emission pattern:
   --    item := ch.receive() -> protected entry call with barrier (Count > 0)
   --  The compiler emits Check_Channel_Not_Empty before the entry call.
   -------------------------------------------------------------------
   procedure Receive
     (Ch   : in out Channel;
      Item : out Element_Type)
   is
   begin
      --  PO hook: verify channel is not empty.
      Check_Channel_Not_Empty (Ch.Count);

      --  Dequeue: read element at Head, advance Head circularly.
      Item := Ch.Buffer (Ch.Head);
      if Ch.Head = Ch.Capacity then
         Ch.Head := 1;
      else
         Ch.Head := Ch.Head + 1;
      end if;
      Ch.Count := Ch.Count - 1;
   end Receive;

end Template_Channel_FIFO;
