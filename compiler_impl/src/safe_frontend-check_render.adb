with Ada.Characters.Latin_1;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Safe_Frontend.Types;

package body Safe_Frontend.Check_Render is
   package FT renames Safe_Frontend.Types;
   package US renames Ada.Strings.Unbounded;

   function Source_Line
     (Source_Text : String;
      Line_No     : Positive) return String
   is
      Current_Line  : Positive := 1;
      Segment_Start : Positive := 1;
   begin
      if Source_Text'Length = 0 then
         return "";
      end if;

      for Index in Source_Text'Range loop
         if Source_Text (Index) = Ada.Characters.Latin_1.LF then
            if Current_Line = Line_No then
               if Index = Segment_Start then
                  return "";
               end if;
               return Source_Text (Segment_Start .. Index - 1);
            end if;
            Current_Line := Current_Line + 1;
            Segment_Start := Index + 1;
         end if;
      end loop;

      if Current_Line = Line_No and then Segment_Start <= Source_Text'Last then
         return Source_Text (Segment_Start .. Source_Text'Last);
      end if;
      return "";
   end Source_Line;

   function Repeat
     (Ch    : Character;
      Count : Natural) return String
   is
   begin
      if Count = 0 then
         return "";
      end if;
      return Result : String (1 .. Count) do
         for Index in Result'Range loop
            Result (Index) := Ch;
         end loop;
      end return;
   end Repeat;

   function Render_Labeled_Block
     (Label : String;
      Text  : String) return String
   is
      Result        : US.Unbounded_String := US.Null_Unbounded_String;
      Segment_Start : Positive := 1;
      First_Line    : Boolean := True;
      procedure Flush (Last : Natural) is
         Segment : constant String :=
           (if Last < Segment_Start then "" else Text (Segment_Start .. Last));
      begin
         if First_Line then
            US.Append (Result, "  " & Label & ": " & Segment & Ada.Characters.Latin_1.LF);
            First_Line := False;
         else
            US.Append (Result, "        " & Segment & Ada.Characters.Latin_1.LF);
         end if;
      end Flush;
   begin
      if Text'Length = 0 then
         return "  " & Label & ": " & Ada.Characters.Latin_1.LF;
      end if;

      for Index in Text'Range loop
         if Text (Index) = Ada.Characters.Latin_1.LF then
            Flush (Index - 1);
            Segment_Start := Index + 1;
         end if;
      end loop;

      if Segment_Start <= Text'Last then
         Flush (Text'Last);
      elsif First_Line then
         Flush (Segment_Start - 1);
      end if;

      return US.To_String (Result);
   end Render_Labeled_Block;

   function Render
     (Diagnostic  : MD.Diagnostic;
      Source_Text : String;
      Path        : String) return String
   is
      Location     : constant FT.Source_Span := Diagnostic.Span;
      Highlight    : constant FT.Source_Span :=
        (if Diagnostic.Has_Highlight_Span then Diagnostic.Highlight_Span else Diagnostic.Span);
      Line_Text    : constant String := Source_Line (Source_Text, Highlight.Start_Pos.Line);
      Line_No      : constant String := FT.Image (Highlight.Start_Pos.Line);
      Marker_Width : constant Positive :=
        Positive'Max
          (1,
           Highlight.End_Pos.Column - Highlight.Start_Pos.Column + 1);
      Marker       : constant String :=
        Repeat (' ', Highlight.Start_Pos.Column - 1)
        & "^"
        & Repeat ('~', Marker_Width - 1);
      Result       : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      US.Append
        (Result,
         Ada.Directories.Simple_Name (Path)
         & ":"
         & FT.Image (Location.Start_Pos.Line)
         & ":"
         & FT.Image (Location.Start_Pos.Column)
         & ": error: "
         & FT.To_String (Diagnostic.Message)
         & Ada.Characters.Latin_1.LF);
      US.Append (Result, "  |" & Ada.Characters.Latin_1.LF);
      US.Append
        (Result,
         "  | "
         & Line_No
         & " | "
         & Line_Text
         & Ada.Characters.Latin_1.LF);
      US.Append
        (Result,
         "  | "
         & Repeat (' ', Line_No'Length + 1)
         & "| "
         & Marker
         & Ada.Characters.Latin_1.LF);
      US.Append (Result, "  |" & Ada.Characters.Latin_1.LF);

      for Note of Diagnostic.Notes loop
         US.Append
           (Result,
            Render_Labeled_Block ("note", FT.To_String (Note)));
      end loop;

      for Suggestion of Diagnostic.Suggestions loop
         US.Append
           (Result,
            Render_Labeled_Block ("suggestion", FT.To_String (Suggestion)));
      end loop;

      return US.To_String (Result);
   end Render;

   function Render
     (Diagnostics : MD.Diagnostic_Vectors.Vector;
      Source_Text : String;
      Path        : String) return String
   is
   begin
      if Diagnostics.Is_Empty then
         return "";
      end if;
      return Render (Diagnostics (Diagnostics.First_Index), Source_Text, Path);
   end Render;
end Safe_Frontend.Check_Render;
