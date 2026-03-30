with Ada.Unchecked_Deallocation;

package body Safe_Ownership_RT is
   pragma SPARK_Mode (Off);

   procedure Free_Access is new Ada.Unchecked_Deallocation (Target_Type, Access_Type);

   function Allocate (Value : Target_Type) return not null Access_Type is
   begin
      return new Target_Type'(Value);
   end Allocate;

   procedure Free (Value : in out Access_Type) is
   begin
      if Value /= null then
         Free_Access (Value);
      end if;
      Value := null;
   end Free;

end Safe_Ownership_RT;
