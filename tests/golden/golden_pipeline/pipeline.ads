pragma SPARK_Mode (On);

package Pipeline
   with SPARK_Mode => On,
        Initializes => (Raw_Ch, Filtered_Ch, Producer, Filter, Consumer)
is
   pragma Elaborate_Body;

   type Sample is range 0 .. 10000;
   subtype Raw_Ch_Index is Positive range 1 .. 4;
   subtype Raw_Ch_Count is Natural range 0 .. 4;
   type Raw_Ch_Buffer is array (Raw_Ch_Index) of Sample;
   protected type Raw_Ch_Channel with Priority => 10 is
      entry Send (Value : in Sample);
      entry Receive (Value : out Sample);
      procedure Try_Send (Value : in Sample; Success : out Boolean);
      procedure Try_Receive (Value : in out Sample; Success : out Boolean);
   private
      Buffer : Raw_Ch_Buffer := (others => Sample'First);
      Head   : Raw_Ch_Index := Raw_Ch_Index'First;
      Tail   : Raw_Ch_Index := Raw_Ch_Index'First;
      Count  : Raw_Ch_Count := 0;
   end Raw_Ch_Channel;
   Raw_Ch : Raw_Ch_Channel;

   subtype Filtered_Ch_Index is Positive range 1 .. 4;
   subtype Filtered_Ch_Count is Natural range 0 .. 4;
   type Filtered_Ch_Buffer is array (Filtered_Ch_Index) of Sample;
   protected type Filtered_Ch_Channel with Priority => 10 is
      entry Send (Value : in Sample);
      entry Receive (Value : out Sample);
      procedure Try_Send (Value : in Sample; Success : out Boolean);
      procedure Try_Receive (Value : in out Sample; Success : out Boolean);
   private
      Buffer : Filtered_Ch_Buffer := (others => Sample'First);
      Head   : Filtered_Ch_Index := Filtered_Ch_Index'First;
      Tail   : Filtered_Ch_Index := Filtered_Ch_Index'First;
      Count  : Filtered_Ch_Count := 0;
   end Filtered_Ch_Channel;
   Filtered_Ch : Filtered_Ch_Channel;

   task Producer with Priority => 10;
   task Filter with Priority => 10;
   task Consumer with Priority => 10;

end Pipeline;
