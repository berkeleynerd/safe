package body pipeline with SPARK_Mode => On is

   protected body raw_ch_Channel is
      entry Send (Value : in sample)
         when Count < 4 is
      begin
         Buffer (Tail) := Value;
         if Tail = raw_ch_Index'Last then
            Tail := raw_ch_Index'First;
         else
            Tail := raw_ch_Index'Succ (Tail);
         end if;
         Count := Count + 1;
      end Send;

      entry Receive (Value : out sample)
         when Count > 0 is
      begin
         Value := Buffer (Head);
         Buffer (Head) := sample'First;
         if Head = raw_ch_Index'Last then
            Head := raw_ch_Index'First;
         else
            Head := raw_ch_Index'Succ (Head);
         end if;
         Count := Count - 1;
      end Receive;

      procedure Try_Send (Value : in sample; Success : out Boolean) is
      begin
         if Count < 4 then
            Buffer (Tail) := Value;
            if Tail = raw_ch_Index'Last then
               Tail := raw_ch_Index'First;
            else
               Tail := raw_ch_Index'Succ (Tail);
            end if;
            Count := Count + 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Send;

      procedure Try_Receive (Value : in out sample; Success : out Boolean) is
      begin
         if Count > 0 then
            Value := Buffer (Head);
            Buffer (Head) := sample'First;
            if Head = raw_ch_Index'Last then
               Head := raw_ch_Index'First;
            else
               Head := raw_ch_Index'Succ (Head);
            end if;
            Count := Count - 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Receive;
   end raw_ch_Channel;

   protected body filtered_ch_Channel is
      entry Send (Value : in sample)
         when Count < 4 is
      begin
         Buffer (Tail) := Value;
         if Tail = filtered_ch_Index'Last then
            Tail := filtered_ch_Index'First;
         else
            Tail := filtered_ch_Index'Succ (Tail);
         end if;
         Count := Count + 1;
      end Send;

      entry Receive (Value : out sample)
         when Count > 0 is
      begin
         Value := Buffer (Head);
         Buffer (Head) := sample'First;
         if Head = filtered_ch_Index'Last then
            Head := filtered_ch_Index'First;
         else
            Head := filtered_ch_Index'Succ (Head);
         end if;
         Count := Count - 1;
      end Receive;

      procedure Try_Send (Value : in sample; Success : out Boolean) is
      begin
         if Count < 4 then
            Buffer (Tail) := Value;
            if Tail = filtered_ch_Index'Last then
               Tail := filtered_ch_Index'First;
            else
               Tail := filtered_ch_Index'Succ (Tail);
            end if;
            Count := Count + 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Send;

      procedure Try_Receive (Value : in out sample; Success : out Boolean) is
      begin
         if Count > 0 then
            Value := Buffer (Head);
            Buffer (Head) := sample'First;
            if Head = filtered_ch_Index'Last then
               Head := filtered_ch_Index'First;
            else
               Head := filtered_ch_Index'Succ (Head);
            end if;
            Count := Count - 1;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Receive;
   end filtered_ch_Channel;

   task body producer is
   begin
      loop
         raw_ch.Send (8);
         delay 0.001;
      end loop;
   end producer;

   task body filter is
      input : sample;
   begin
      loop
         raw_ch.Receive (input);
         filtered_ch.Send (input);
         delay 0.001;
      end loop;
   end filter;

   task body consumer is
      data : sample;
   begin
      loop
         filtered_ch.Receive (data);
         if (data > 0) then
            delay 0.001;
         else
            delay 0.001;
         end if;
         delay 0.001;
      end loop;
   end consumer;

end pipeline;
