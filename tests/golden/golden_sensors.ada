--  Golden output: Expected Ada/SPARK translation of rule1_averaging.safe
--  Source: tests/positive/rule1_averaging.safe
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126:812b54a8
--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p127:d5d93439
--  Clause: SAFE@468cf72:spec/05-assurance.md#5.3.6.p25:e8253bd7
--
--  The Safe compiler translates wide intermediate arithmetic into
--  Long_Long_Integer operations and inserts explicit range assertions
--  at narrowing points (assignment, return).

pragma SPARK_Mode (On);
pragma Assertion_Policy (Check);

package Sensor_Average
  with SPARK_Mode => On
is

   type Reading is range 0 .. 1000;
   type Sensor_Count is range 1 .. 10;
   type Readings is array (Sensor_Count) of Reading;

   function Average (Data : Readings) return Reading
     with Post => Average'Result >= 0
                  and then Average'Result <= 1000;

end Sensor_Average;

pragma SPARK_Mode (On);

package body Sensor_Average
  with SPARK_Mode => On
is

   function Average (Data : Readings) return Reading is
      --  Wide intermediate: sum computed in Long_Long_Integer.
      Sum : Long_Long_Integer := 0;
   begin
      for I in Sensor_Count loop
         --  Intermediate: Sum is in 0 .. (I-1)*1000 before addition.
         --  After: Sum is in 0 .. I*1000. Maximum: 10*1000 = 10_000.
         pragma Assert (Sum >= 0);
         pragma Assert (Sum <= Long_Long_Integer (I - 1) * 1000);

         Sum := Sum + Long_Long_Integer (Data (I));

         pragma Assert (Sum >= 0);
         pragma Assert (Sum <= Long_Long_Integer (I) * 1000);
      end loop;

      --  Post-loop: Sum is in 0 .. 10_000.
      pragma Assert (Sum >= 0 and Sum <= 10_000);

      --  Narrowing point (return): Sum / 10 is in 0 .. 1000.
      --  Division by 10 (nonzero literal).
      pragma Assert (Sum / 10 >= 0 and Sum / 10 <= 1000);

      return Reading (Sum / 10);
   end Average;

end Sensor_Average;
