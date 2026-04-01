--  Verified Emission Template: Dispatcher-Based Select Lowering
--  See template_select_dispatcher.ads for clause references.

pragma SPARK_Mode (On);

with Safe_PO; use Safe_PO;

package body Template_Select_Dispatcher
  with SPARK_Mode => On
is

   procedure Reset (D : in out Dispatcher) is
   begin
      D.Signaled := False;
      D.Delay_Expired := False;
   end Reset;

   procedure Signal (D : in out Dispatcher) is
   begin
      D.Signaled := True;
      D.Delay_Expired := False;
   end Signal;

   procedure Signal_Delay (D : in out Dispatcher) is
   begin
      D.Signaled := True;
      D.Delay_Expired := True;
   end Signal_Delay;

   procedure Await (D : in out Dispatcher; Timed_Out : out Boolean) is
   begin
      Timed_Out := D.Delay_Expired;
      D.Signaled := False;
      D.Delay_Expired := False;
   end Await;

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
   --    Source-order precheck tests arms in declaration order.
   --    When neither arm is ready, the dispatcher awaits either:
   --      * a channel wake from a successful send
   --      * the one-shot delay wake from the timing handler
   --    A bounded wake schedule models the finite environment trace.
   -------------------------------------------------------------------
   procedure Select_With_Delay
     (Ch_A      : in out Channel;
      Ch_B      : in out Channel;
      Wakeups   : Delay_Wake_Schedule;
      Result    : out Element_Type;
      Timed_Out : out Boolean)
   is
      Select_Done : Boolean := False;
      Success     : Boolean;
      Item        : Element_Type;
      Disp        : Dispatcher := (Signaled => False, Delay_Expired => False);
      Timed_Wake  : Boolean := False;
   begin
      Result    := Default_Element;
      Timed_Out := False;
      Reset (Disp);

      for Iter in Wake_Range loop
         pragma Loop_Invariant (Is_Valid (Ch_A));
         pragma Loop_Invariant (Is_Valid (Ch_B));
         pragma Loop_Invariant (not Timed_Out);
         pragma Loop_Invariant (Is_Idle (Disp));
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

         --  Dispatcher wait: either a channel wake or the delay handler.
         if not Select_Done then
            case Wakeups (Iter) is
               when No_Wake =>
                  null;
               when Channel_Wake =>
                  Signal (Disp);
                  Await (Disp, Timed_Wake);
                  pragma Assert (not Timed_Wake);
               when Delay_Wake =>
                  Signal_Delay (Disp);
                  Await (Disp, Timed_Wake);
                  if Timed_Wake then
                     Timed_Out := True;
                     Select_Done := True;
                  end if;
            end case;
         end if;

         exit when Select_Done;
      end loop;
   end Select_With_Delay;

   -------------------------------------------------------------------
   --  Select_No_Delay: two-arm select without delay arm
   --
   --  Emission pattern from translation_rules.md Section 5:
   --    Source-order precheck tests arms in declaration order.
   --    When neither arm is ready, the dispatcher blocks until a channel
   --    wake arrives; the bounded wake schedule models a finite trace.
   -------------------------------------------------------------------
   procedure Select_No_Delay
     (Ch_A   : in out Channel;
      Ch_B   : in out Channel;
      Wakeups : Channel_Wake_Schedule;
      Result : out Element_Type;
      Found  : out Boolean)
   is
      Select_Done : Boolean := False;
      Success     : Boolean;
      Item        : Element_Type;
      Disp        : Dispatcher := (Signaled => False, Delay_Expired => False);
      Timed_Wake  : Boolean := False;
   begin
      Result := Default_Element;
      Found  := False;
      Reset (Disp);

      for Iter in Wake_Range loop
         pragma Loop_Invariant (Is_Valid (Ch_A));
         pragma Loop_Invariant (Is_Valid (Ch_B));
         pragma Loop_Invariant (not Found);
         pragma Loop_Invariant (Is_Idle (Disp));
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
         elsif Wakeups (Iter) then
            Signal (Disp);
            Await (Disp, Timed_Wake);
            pragma Assert (not Timed_Wake);
         end if;

         exit when Select_Done;
      end loop;
   end Select_No_Delay;

end Template_Select_Dispatcher;
