package body Safe_Array_Identity_Ops is
   function Default return Element is (Default_Element);

   function Clone (Source : Element) return Element is
     (Clone_Element (Source));

   procedure Free (Value : in out Element) is
   begin
      Free_Element (Value);
   end Free;
end Safe_Array_Identity_Ops;
