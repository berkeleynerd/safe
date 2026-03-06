with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;

package body Safe_Frontend.Json is
   package US renames Ada.Strings.Unbounded;
   package FT renames Safe_Frontend.Types;

   Backslash : constant Character := Character'Val (16#5C#);

   function Escape (Item : String) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      for Ch of Item loop
         case Ch is
            when '"' =>
               US.Append (Result, Backslash);
               US.Append (Result, Character'Val (34));
            when Backslash =>
               US.Append (Result, Backslash);
               US.Append (Result, Backslash);
            when Ada.Characters.Latin_1.LF =>
               US.Append (Result, Backslash);
               US.Append (Result, 'n');
            when Ada.Characters.Latin_1.CR =>
               US.Append (Result, Backslash);
               US.Append (Result, 'r');
            when Ada.Characters.Latin_1.HT =>
               US.Append (Result, Backslash);
               US.Append (Result, 't');
            when others =>
               US.Append (Result, Ch);
         end case;
      end loop;
      return US.To_String (Result);
   end Escape;

   function Quote (Item : String) return String is
   begin
      return Character'Val (34) & Escape (Item) & Character'Val (34);
   end Quote;

   function Bool_Literal (Item : Boolean) return String is
   begin
      if Item then
         return "true";
      end if;
      return "false";
   end Bool_Literal;

   function Quote (Item : FT.UString) return String is
   begin
      return Quote (FT.To_String (Item));
   end Quote;

   function Span_Object (Span : FT.Source_Span) return String is
   begin
      return
        "{"
        & """start_line"":"
        & FT.Image (Span.Start_Pos.Line)
        & ","
        & """start_col"":"
        & FT.Image (Span.Start_Pos.Column)
        & ","
        & """end_line"":"
        & FT.Image (Span.End_Pos.Line)
        & ","
        & """end_col"":"
        & FT.Image (Span.End_Pos.Column)
        & "}";
   end Span_Object;
end Safe_Frontend.Json;
