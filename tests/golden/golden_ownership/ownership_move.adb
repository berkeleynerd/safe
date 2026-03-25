with Ada.Unchecked_Deallocation;

package body Ownership_Move with SPARK_Mode => On is

   procedure Transfer is
      Source : Payload_Ptr := new Payload'(Value => 42);
      Target : Payload_Ptr := null;
      procedure Free_Payload_Ptr is new Ada.Unchecked_Deallocation (Payload, Payload_Ptr);
   begin
      Target := Source;
      Source := null;
      Target.all.Value := 100;
      Free_Payload_Ptr (Target);
      Free_Payload_Ptr (Source);
   end Transfer;

end Ownership_Move;
