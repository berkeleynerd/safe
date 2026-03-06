with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Safe_Frontend.Diagnostics is
   package US renames Ada.Strings.Unbounded;

   procedure Add_Error
     (Collection : in out Diagnostic_Vectors.Vector;
      Path       : String;
      Span       : FT.Source_Span;
      Code       : String;
      Message    : String;
      Note       : String := "";
      Suggestion : String := "")
   is
      Item : constant Diagnostic :=
        (Path       => FT.To_UString (Path),
         Span       => Span,
         Severity   => Error_Severity,
         Code       => FT.To_UString (Code),
         Message    => FT.To_UString (Message),
         Note       => FT.To_UString (Note),
         Suggestion => FT.To_UString (Suggestion));
   begin
      Collection.Append (Item);
   end Add_Error;

   function Has_Errors (Collection : Diagnostic_Vectors.Vector) return Boolean is
   begin
      return not Collection.Is_Empty;
   end Has_Errors;

   function Format (Collection : Diagnostic_Vectors.Vector) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      for Item of Collection loop
         US.Append
           (Result,
            FT.To_String (Item.Path)
            & ":"
            & FT.Image (Item.Span.Start_Pos.Line)
            & ":"
            & FT.Image (Item.Span.Start_Pos.Column)
            & ": error["
            & FT.To_String (Item.Code)
            & "]: "
            & FT.To_String (Item.Message)
            & Ada.Characters.Latin_1.LF);
         if FT.To_String (Item.Note)'Length > 0 then
            US.Append
              (Result,
               "  note: " & FT.To_String (Item.Note) & Ada.Characters.Latin_1.LF);
         end if;
         if FT.To_String (Item.Suggestion)'Length > 0 then
            US.Append
              (Result,
               "  help: " & FT.To_String (Item.Suggestion) & Ada.Characters.Latin_1.LF);
         end if;
      end loop;
      return US.To_String (Result);
   end Format;

   procedure Print (Collection : Diagnostic_Vectors.Vector) is
   begin
      if not Collection.Is_Empty then
         Ada.Text_IO.Put (Ada.Text_IO.Current_Error, Format (Collection));
      end if;
   end Print;
end Safe_Frontend.Diagnostics;
