pragma SPARK_Mode (On);

package pipeline
   with SPARK_Mode => On,
        Initializes => (raw_ch, filtered_ch, producer, filter, consumer)
is
   pragma Elaborate_Body;

   type sample is range 0 .. 10000;
   subtype raw_ch_Index is Positive range 1 .. 4;
   subtype raw_ch_Count is Natural range 0 .. 4;
   type raw_ch_Buffer is array (raw_ch_Index) of sample;
   protected type raw_ch_Channel with Priority => 10 is
      entry Send (Value : in sample);
      entry Receive (Value : out sample);
      procedure Try_Send (Value : in sample; Success : out Boolean);
      procedure Try_Receive (Value : in out sample; Success : out Boolean);
   private
      Buffer : raw_ch_Buffer := (others => sample'First);
      Head   : raw_ch_Index := raw_ch_Index'First;
      Tail   : raw_ch_Index := raw_ch_Index'First;
      Count  : raw_ch_Count := 0;
   end raw_ch_Channel;
   raw_ch : raw_ch_Channel;

   subtype filtered_ch_Index is Positive range 1 .. 4;
   subtype filtered_ch_Count is Natural range 0 .. 4;
   type filtered_ch_Buffer is array (filtered_ch_Index) of sample;
   protected type filtered_ch_Channel with Priority => 10 is
      entry Send (Value : in sample);
      entry Receive (Value : out sample);
      procedure Try_Send (Value : in sample; Success : out Boolean);
      procedure Try_Receive (Value : in out sample; Success : out Boolean);
   private
      Buffer : filtered_ch_Buffer := (others => sample'First);
      Head   : filtered_ch_Index := filtered_ch_Index'First;
      Tail   : filtered_ch_Index := filtered_ch_Index'First;
      Count  : filtered_ch_Count := 0;
   end filtered_ch_Channel;
   filtered_ch : filtered_ch_Channel;

   task producer with Priority => 10;
   task filter with Priority => 10;
   task consumer with Priority => 10;

end pipeline;
