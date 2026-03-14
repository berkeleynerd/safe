with Safe_Runtime;
use type Safe_Runtime.Wide_Integer;

package body Sensor_Average with SPARK_Mode => On is

   function Average(Data : Readings) return Reading is
      Sum : Safe_Runtime.Wide_Integer := Safe_Runtime.Wide_Integer (0);
   begin
      for I in Sensor_Count loop
         Sum := (Safe_Runtime.Wide_Integer (Sum) + Safe_Runtime.Wide_Integer (Data (I)));
      end loop;
      pragma Assert ((Safe_Runtime.Wide_Integer (Sum) / Safe_Runtime.Wide_Integer (10)) >= Safe_Runtime.Wide_Integer (Reading'First) and then (Safe_Runtime.Wide_Integer (Sum) / Safe_Runtime.Wide_Integer (10)) <= Safe_Runtime.Wide_Integer (Reading'Last));
      return Reading ((Safe_Runtime.Wide_Integer (Sum) / Safe_Runtime.Wide_Integer (10)));
   end Average;

end Sensor_Average;
