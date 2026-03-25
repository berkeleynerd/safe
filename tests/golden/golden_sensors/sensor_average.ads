pragma SPARK_Mode (On);

package Sensor_Average
   with SPARK_Mode => On,
        Initializes => null
is
   pragma Elaborate_Body;

   type Reading is range 0 .. 1000;
   type Sensor_Count is range 1 .. 10;
   type Readings is array (Sensor_Count) of Reading;
   function Average(Data : Readings) return Reading with Global => null,
            Depends => (Average'Result => Data);

end Sensor_Average;
