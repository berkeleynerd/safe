package body Pipeline with SPARK_Mode => On is

   protected body Raw_Ch_Channel is
      entry Send (Value : in Sample)
         when Count < 4 is
      begin
         Buffer (Tail) := Value;
         if Tail = Raw_Ch_Index'Last then
            Tail := Raw_Ch_Index'First;
         else
            Tail := Raw_Ch_Index'Succ (Tail);
         end if;
         Count := Count + 1;
      end Send;

      entry Receive (Value : out Sample)
         when Count > 0 is
      begin
         Value := Buffer (Head);
         if Head = Raw_Ch_Index'Last then
            Head := Raw_Ch_Index'First;
         else
            Head := Raw_Ch_Index'Succ (Head);
         end if;
         Count := Count - 1;
      end Receive;

      procedure Try_Send (Value : in Sample; Success : out Boolean) is
      begin
         if Count < 4 then
            Buffer (Tail) := Value;
            if Tail = Raw_Ch_Index'Last then
               Tail := Raw_Ch_Index'First;
            else
               Tail := Raw_Ch_Index'Succ (Tail);
            end if;
            Count := Count + 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Send;

      procedure Try_Receive (Value : out Sample; Success : out Boolean) is
      begin
         if Count > 0 then
            Value := Buffer (Head);
            if Head = Raw_Ch_Index'Last then
               Head := Raw_Ch_Index'First;
            else
               Head := Raw_Ch_Index'Succ (Head);
            end if;
            Count := Count - 1;
            Success := True;
         else
            Value := Sample'First;
            Success := False;
         end if;
      end Try_Receive;
   end Raw_Ch_Channel;

   protected body Filtered_Ch_Channel is
      entry Send (Value : in Sample)
         when Count < 4 is
      begin
         Buffer (Tail) := Value;
         if Tail = Filtered_Ch_Index'Last then
            Tail := Filtered_Ch_Index'First;
         else
            Tail := Filtered_Ch_Index'Succ (Tail);
         end if;
         Count := Count + 1;
      end Send;

      entry Receive (Value : out Sample)
         when Count > 0 is
      begin
         Value := Buffer (Head);
         if Head = Filtered_Ch_Index'Last then
            Head := Filtered_Ch_Index'First;
         else
            Head := Filtered_Ch_Index'Succ (Head);
         end if;
         Count := Count - 1;
      end Receive;

      procedure Try_Send (Value : in Sample; Success : out Boolean) is
      begin
         if Count < 4 then
            Buffer (Tail) := Value;
            if Tail = Filtered_Ch_Index'Last then
               Tail := Filtered_Ch_Index'First;
            else
               Tail := Filtered_Ch_Index'Succ (Tail);
            end if;
            Count := Count + 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Send;

      procedure Try_Receive (Value : out Sample; Success : out Boolean) is
      begin
         if Count > 0 then
            Value := Buffer (Head);
            if Head = Filtered_Ch_Index'Last then
               Head := Filtered_Ch_Index'First;
            else
               Head := Filtered_Ch_Index'Succ (Head);
            end if;
            Count := Count - 1;
            Success := True;
         else
            Value := Sample'First;
            Success := False;
         end if;
      end Try_Receive;
   end Filtered_Ch_Channel;

   procedure Produce_Once is
   begin
      Raw_Ch.Send (8);
   end Produce_Once;

   procedure Filter_Once is
      Input : Sample;
   begin
      Raw_Ch.Receive (Input);
      Filtered_Ch.Send (Input);
   end Filter_Once;

   procedure Consume_Once(Seen : out Boolean) is
      Data : Sample;
   begin
      Filtered_Ch.Receive (Data);
      Seen := (Data > 0);
   end Consume_Once;

   task body Producer is
   begin
      loop
         delay 0.001;
      end loop;
   end Producer;

   task body Filter is
   begin
      loop
         delay 0.001;
      end loop;
   end Filter;

   task body Consumer is
   begin
      loop
         delay 0.001;
      end loop;
   end Consumer;

end Pipeline;
