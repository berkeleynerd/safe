with Safe_Frontend.Mir_Model;

package Safe_Frontend.Builtin_Types is
   package GM renames Safe_Frontend.Mir_Model;

   function Integer_Type return GM.Type_Descriptor;
   function Boolean_Type return GM.Type_Descriptor;
   function Character_Type return GM.Type_Descriptor;
   function String_Type return GM.Type_Descriptor;
   function Result_Type return GM.Type_Descriptor;
   function Float_Type (With_Analysis_Metadata : Boolean := False) return GM.Type_Descriptor;
   function Long_Float_Type (With_Analysis_Metadata : Boolean := False) return GM.Type_Descriptor;
   function Duration_Type (With_Analysis_Metadata : Boolean := False) return GM.Type_Descriptor;
end Safe_Frontend.Builtin_Types;
