with Ada.Unchecked_Deallocation;

package body ownership_move with SPARK_Mode => On is

   procedure transfer is
      Source : payload_ptr := new payload'(value => 42);
      Target : payload_ptr := null;
      procedure Free_payload_ptr is new Ada.Unchecked_Deallocation (payload, payload_ptr);
   begin
      Target := Source;
      Source := null;
      Target.all.value := 100;
      Free_payload_ptr (Target);
      Free_payload_ptr (Source);
   end transfer;

end ownership_move;
