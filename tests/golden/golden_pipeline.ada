--  Golden output: Expected Ada/SPARK translation of channel_pipeline.safe
--  Source: tests/positive/channel_pipeline.safe
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.1.p2:78f022f7
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p15:b5b29b0e
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p27:ef0ce6bd
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p28:ea6bd13c
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.2.p20:8aa1a21e
--  Clause: SAFE@468cf72:spec/04-tasks-and-channels.md#4.3.p31:a7297e97
--
--  The Safe compiler translates channels into protected objects with
--  ceiling priority, and task declarations into Ada task objects.
--  Channel operations become calls to the protected object's entries.

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

with System;

package Pipeline
  with SPARK_Mode => On
is

   type Sample is range 0 .. 10_000;

private

   --  Channel backing: bounded FIFO as protected object.
   --  Capacity 4 for both channels.

   type Sample_Buffer is array (1 .. 4) of Sample;

   protected type Channel_Sample_4 is
      pragma Priority (System.Default_Priority);

      entry Send (Item : in Sample);
      entry Receive (Item : out Sample);

      function Length return Natural;
   private
      Buffer : Sample_Buffer := (others => 0);
      Head   : Natural := 1;
      Tail   : Natural := 1;
      Count  : Natural := 0;
   end Channel_Sample_4;

   Raw_Ch      : Channel_Sample_4;
   Filtered_Ch : Channel_Sample_4;

   --  Task declarations: one per Safe task.
   task Producer_Task;
   task Filter_Task;
   task Consumer_Task;

end Pipeline;

pragma SPARK_Mode (On);

package body Pipeline
  with SPARK_Mode => On
is

   protected body Channel_Sample_4 is

      entry Send (Item : in Sample)
        when Count < 4 is
      begin
         Buffer (Tail) := Item;
         Tail := (Tail mod 4) + 1;
         Count := Count + 1;
      end Send;

      entry Receive (Item : out Sample)
        when Count > 0 is
      begin
         Item := Buffer (Head);
         Head := (Head mod 4) + 1;
         Count := Count - 1;
      end Receive;

      function Length return Natural is
      begin
         return Count;
      end Length;

   end Channel_Sample_4;

   task body Producer_Task is
      Counter : Sample := 0;
   begin
      loop
         Raw_Ch.Send (Counter);
         if Counter < 10_000 then
            Counter := Counter + 1;
         else
            Counter := 0;
         end if;
      end loop;
   end Producer_Task;

   task body Filter_Task is
      Input  : Sample;
      Output : Sample;
   begin
      loop
         Raw_Ch.Receive (Input);
         --  Division by 2 (nonzero literal): safe.
         Output := Input / 2;
         Filtered_Ch.Send (Output);
      end loop;
   end Filter_Task;

   task body Consumer_Task is
      Data : Sample;
      Sum  : Natural := 0;
   begin
      loop
         Filtered_Ch.Receive (Data);
         Sum := Sum + Natural (Data);
         if Sum > 1_000_000 then
            Sum := 0;
         end if;
      end loop;
   end Consumer_Task;

end Pipeline;
