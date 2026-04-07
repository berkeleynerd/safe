package body Safe_Frontend.Name_Utils is

   function Trim_Edge_Underscores
     (Value         : String;
      Fallback_Text : String := "") return String
   is
      First : Positive := Value'First;
      Last  : Natural := Value'Last;
   begin
      while First <= Value'Last and then Value (First) = '_' loop
         First := First + 1;
      end loop;

      while Last >= First and then Value (Last) = '_' loop
         Last := Last - 1;
      end loop;

      if Last < First then
         return Fallback_Text;
      end if;

      return Value (First .. Last);
   end Trim_Edge_Underscores;

   function Sanitize_Type_Name_Component (Value : String) return String is
      Result              : FT.UString := FT.To_UString ("");
      Last_Was_Underscore : Boolean := False;
   begin
      for Ch of Value loop
         if Ch in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
            Result := FT.US."&" (Result, FT.To_UString ((1 => Ch)));
            Last_Was_Underscore := False;
         elsif not Last_Was_Underscore then
            Result := FT.US."&" (Result, FT.To_UString ("_"));
            Last_Was_Underscore := True;
         end if;
      end loop;

      return Trim_Edge_Underscores (FT.To_String (Result), "value");
   end Sanitize_Type_Name_Component;

   function Sanitize_Type_Name_Component_Trimmed (Value : String) return String is
   begin
      return
        Trim_Edge_Underscores
          (Sanitize_Type_Name_Component_Raw (Value), "value");
   end Sanitize_Type_Name_Component_Trimmed;

   function Sanitize_Type_Name_Component_Raw (Value : String) return String is
      Result : FT.UString := FT.To_UString ("");
   begin
      for Ch of Value loop
         if Ch in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
            Result := FT.US."&" (Result, FT.To_UString ((1 => Ch)));
         else
            Result := FT.US."&" (Result, FT.To_UString ("_"));
         end if;
      end loop;

      return FT.To_String (Result);
   end Sanitize_Type_Name_Component_Raw;

end Safe_Frontend.Name_Utils;
