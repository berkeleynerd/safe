pragma SPARK_Mode (On);

generic
   type Element_Type is private;
   --  GNAT does not allow contract aspects on generic formal subprograms here.
   --  The stronger identity obligation is discharged by the concrete emitted
   --  helper actuals passed into this generic wrapper.
   with function Default_Element return Element_Type;
   with function Clone_Element (Source : Element_Type) return Element_Type;
   with procedure Free_Element (Value : in out Element_Type);
package Safe_Array_Identity_Ops is
   subtype Element is Element_Type;

   function Default return Element
      with Global => null;
   function Clone (Source : Element) return Element
      with Global => null,
           Post => Clone'Result = Source;
   procedure Free (Value : in out Element)
      with Global => null,
           Always_Terminates,
           Depends => (Value => Value);
end Safe_Array_Identity_Ops;
