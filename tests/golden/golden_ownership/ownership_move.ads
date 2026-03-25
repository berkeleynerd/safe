pragma SPARK_Mode (On);

package ownership_move
   with SPARK_Mode => On,
        Initializes => null
is
   pragma Elaborate_Body;

   type payload is record
   value : integer;
end record;

   type payload_ptr is access payload;
   procedure transfer with Global => null;

end ownership_move;
