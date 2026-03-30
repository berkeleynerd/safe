pragma SPARK_Mode (On);

package body Safe_Bounded_Strings is
   package body Generic_Bounded_String is
      function To_Bounded (Value : String) return Bounded_String is
         Result : Bounded_String := Empty;
      begin
         Result.Length := Value'Length;
         if Value'Length > 0 then
            Result.Data (1 .. Value'Length) := Value;
         end if;
         return Result;
      end To_Bounded;

      function Slice_Bounded (Value : Bounded_String; Low, High : Positive) return Bounded_String is
         Result : Bounded_String := Empty;
         Span   : constant Natural := High - Low + 1;
      begin
         pragma Assert (Low in Value.Data'Range);
         pragma Assert (High in Value.Data'Range);
         Result.Length := Span;
         Result.Data (1 .. Span) := Value.Data (Low .. High);
         return Result;
      end Slice_Bounded;

   end Generic_Bounded_String;
end Safe_Bounded_Strings;
