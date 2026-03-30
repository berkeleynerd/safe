with Ada.Text_IO;

package body IO
  with SPARK_Mode => Off
is
   procedure Put_Line (Text : String) is
   begin
      Ada.Text_IO.Put_Line (Text);
   end Put_Line;
end IO;
