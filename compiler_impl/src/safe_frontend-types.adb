with Ada.Characters.Handling;
with Ada.Strings.Fixed;

package body Safe_Frontend.Types is
   function Image (Item : Positive) return String is
   begin
      return Ada.Strings.Fixed.Trim (Positive'Image (Item), Ada.Strings.Both);
   end Image;

   function Lowercase (Item : String) return String is
      Result : String := Item;
   begin
      for Index in Result'Range loop
         Result (Index) := Ada.Characters.Handling.To_Lower (Result (Index));
      end loop;
      return Result;
   end Lowercase;

   function Span_Image (Span : Source_Span) return String is
   begin
      return
        Image (Span.Start_Pos.Line)
        & ":"
        & Image (Span.Start_Pos.Column)
        & "-"
        & Image (Span.End_Pos.Line)
        & ":"
        & Image (Span.End_Pos.Column);
   end Span_Image;
end Safe_Frontend.Types;
