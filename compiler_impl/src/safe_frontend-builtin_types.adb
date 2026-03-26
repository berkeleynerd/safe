with Safe_Frontend.Types;

package body Safe_Frontend.Builtin_Types is
   package FT renames Safe_Frontend.Types;

   function Make_Integer_Range_Type
     (Name : String;
      Low  : Long_Long_Integer;
      High : Long_Long_Integer) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := FT.To_UString (Name);
      Result.Kind := FT.To_UString ("integer");
      Result.Has_Low := True;
      Result.Low := Low;
      Result.Has_High := True;
      Result.High := High;
      return Result;
   end Make_Integer_Range_Type;

   function Make_Float_Type
     (Name                   : String;
      With_Analysis_Metadata : Boolean) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := FT.To_UString (Name);
      Result.Kind := FT.To_UString ("float");
      if With_Analysis_Metadata then
         Result.Has_Digits_Text := True;
         Result.Digits_Text :=
           FT.To_UString ((if Name = "float" then "6" else "15"));
         Result.Has_Float_Low_Text := True;
         Result.Float_Low_Text := FT.To_UString ("-1.0E+308");
         Result.Has_Float_High_Text := True;
         Result.Float_High_Text := FT.To_UString ("1.0E+308");
      end if;
      return Result;
   end Make_Float_Type;

   function Integer_Type return GM.Type_Descriptor is
   begin
      return Make_Integer_Range_Type ("integer", -(2 ** 63), (2 ** 63) - 1);
   end Integer_Type;

   function Natural_Type return GM.Type_Descriptor is
   begin
      return Make_Integer_Range_Type ("natural", 0, (2 ** 63) - 1);
   end Natural_Type;

   function Boolean_Type return GM.Type_Descriptor is
   begin
      return Make_Integer_Range_Type ("boolean", 0, 1);
   end Boolean_Type;

   function Character_Type return GM.Type_Descriptor is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := FT.To_UString ("character");
      Result.Kind := FT.To_UString ("character");
      return Result;
   end Character_Type;

   function String_Type return GM.Type_Descriptor is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := FT.To_UString ("string");
      Result.Kind := FT.To_UString ("array");
      Result.Has_Component_Type := True;
      Result.Component_Type := FT.To_UString ("character");
      Result.Unconstrained := True;
      return Result;
   end String_Type;

   function Result_Type return GM.Type_Descriptor is
      Result : GM.Type_Descriptor;
      Field  : GM.Type_Field;
   begin
      Result.Name := FT.To_UString ("result");
      Result.Kind := FT.To_UString ("record");
      Result.Is_Result_Builtin := True;

      Field.Name := FT.To_UString ("ok");
      Field.Type_Name := FT.To_UString ("boolean");
      Result.Fields.Append (Field);

      Field.Name := FT.To_UString ("message");
      Field.Type_Name := FT.To_UString ("string");
      Result.Fields.Append (Field);

      return Result;
   end Result_Type;

   function Float_Type (With_Analysis_Metadata : Boolean := False) return GM.Type_Descriptor is
   begin
      return Make_Float_Type ("float", With_Analysis_Metadata);
   end Float_Type;

   function Long_Float_Type (With_Analysis_Metadata : Boolean := False) return GM.Type_Descriptor is
   begin
      return Make_Float_Type ("long_float", With_Analysis_Metadata);
   end Long_Float_Type;

   function Duration_Type (With_Analysis_Metadata : Boolean := False) return GM.Type_Descriptor is
   begin
      return Make_Float_Type ("duration", With_Analysis_Metadata);
   end Duration_Type;
end Safe_Frontend.Builtin_Types;
