pragma SPARK_Mode (On);

package sensor_average
   with SPARK_Mode => On,
        Initializes => null
is
   pragma Elaborate_Body;

   type reading is range 0 .. 1000;
   type sensor_count is range 1 .. 10;
   type readings is array (sensor_count) of reading;
   function average(data : readings) return reading with Global => null,
            Depends => (average'Result => data);

end sensor_average;
