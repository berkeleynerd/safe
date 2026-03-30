pragma SPARK_Mode (On);

package IO is
   procedure Put_Line (Text : String)
     with Global => null,
          Always_Terminates;
end IO;
