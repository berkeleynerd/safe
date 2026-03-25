pragma SPARK_Mode (On);

package Ownership_Move
   with SPARK_Mode => On,
        Initializes => null
is
   pragma Elaborate_Body;

   type Payload is record
   Value : Integer;
end record;

   type Payload_Ptr is access Payload;
   procedure Transfer with Global => null;

end Ownership_Move;
