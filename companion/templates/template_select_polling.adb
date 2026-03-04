--  Verified Emission Template: Select-to-Polling-Loop Lowering
--  See template_select_polling.ads for clause references.

pragma SPARK_Mode (On);

with Safe_PO; use Safe_PO;

package body Template_Select_Polling
  with SPARK_Mode => On
is

   -------------------------------------------------------------------
   --  Try_Receive: non-blocking receive
   --
   --  Emission pattern from translation_rules.md Section 5.1:
   --    If channel is non-empty, dequeue and set Success := True.
   --    Otherwise, set Item := Default_Element and Success := False.
   --  The PO hook Check_Channel_Not_Empty is called when Count > 0.
   -------------------------------------------------------------------
   procedure Try_Receive
     (Ch      : in out Channel;
      Item    : out Element_Type;
      Success : out Boolean)
   is
   begin
      if Ch.Count > 0 then
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
         Success := True;
      else
         --  Channel empty: no item available.
         Item := Default_Element;
         Success := False;
      end if;
   end Try_Receive;

   -------------------------------------------------------------------
   --  Select_With_Delay: two-arm select with delay arm
   --
   --  Emission pattern from translation_rules.md Section 5:
   --    Bounded polling loop tests arms in declaration order.
   --    Arm 1 = Ch_A, Arm 2 = Ch_B, Delay arm = Deadline_Elapsed.
   --    Loop exits when an arm fires or deadline elapses.
   -------------------------------------------------------------------
   procedure Select_With_Delay
     (Ch_A             : in out Channel;
      Ch_B             : in out Channel;
      Deadline_Elapsed : Boolean;
      Result           : out Element_Type;
      Timed_Out        : out Boolean)
   is
      Select_Done : Boolean := False;
      Success     : Boolean;
      Item        : Element_Type;
   begin
      Result    := Default_Element;
      Timed_Out := False;

      for Iter in 1 .. Max_Poll_Iterations loop
         pragma Loop_Invariant (Is_Valid (Ch_A));
         pragma Loop_Invariant (Is_Valid (Ch_B));
         pragma Loop_Invariant (not Select_Done);
         pragma Loop_Invariant (not Timed_Out);
         pragma Loop_Invariant
           (Ch_A.Count = Ch_A.Count'Loop_Entry
            and then Ch_B.Count = Ch_B.Count'Loop_Entry);

         --  Arm 1: Ch_A (highest priority per declaration order).
         Try_Receive (Ch_A, Item, Success);
         if Success then
            Result := Item;
            Select_Done := True;
         end if;

         --  Arm 2: Ch_B (tested only if Arm 1 did not fire).
         if not Select_Done then
            Try_Receive (Ch_B, Item, Success);
            if Success then
               Result := Item;
               Select_Done := True;
            end if;
         end if;

         --  Delay arm: check deadline (tested only if no channel arm fired).
         if not Select_Done then
            if Deadline_Elapsed then
               Timed_Out := True;
               Select_Done := True;
            end if;
         end if;

         exit when Select_Done;
      end loop;
   end Select_With_Delay;

   -------------------------------------------------------------------
   --  Select_No_Delay: two-arm select without delay arm
   --
   --  Emission pattern from translation_rules.md Section 5:
   --    Bounded polling loop tests arms in declaration order.
   --    No delay arm; loop runs until an arm fires or iterations
   --    are exhausted.
   -------------------------------------------------------------------
   procedure Select_No_Delay
     (Ch_A   : in out Channel;
      Ch_B   : in out Channel;
      Result : out Element_Type;
      Found  : out Boolean)
   is
      Select_Done : Boolean := False;
      Success     : Boolean;
      Item        : Element_Type;
   begin
      Result := Default_Element;
      Found  := False;

      for Iter in 1 .. Max_Poll_Iterations loop
         pragma Loop_Invariant (Is_Valid (Ch_A));
         pragma Loop_Invariant (Is_Valid (Ch_B));
         pragma Loop_Invariant (not Select_Done);
         pragma Loop_Invariant (not Found);
         pragma Loop_Invariant
           (Ch_A.Count = Ch_A.Count'Loop_Entry
            and then Ch_B.Count = Ch_B.Count'Loop_Entry);

         --  Arm 1: Ch_A (highest priority per declaration order).
         Try_Receive (Ch_A, Item, Success);
         if Success then
            Result := Item;
            Select_Done := True;
         end if;

         --  Arm 2: Ch_B (tested only if Arm 1 did not fire).
         if not Select_Done then
            Try_Receive (Ch_B, Item, Success);
            if Success then
               Result := Item;
               Select_Done := True;
            end if;
         end if;

         if Select_Done then
            Found := True;
         end if;

         exit when Select_Done;
      end loop;
   end Select_No_Delay;

end Template_Select_Polling;
