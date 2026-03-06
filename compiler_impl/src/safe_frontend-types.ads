with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;

package Safe_Frontend.Types is
   package US renames Ada.Strings.Unbounded;

   subtype UString is US.Unbounded_String;

   function To_UString (Item : String) return UString renames US.To_Unbounded_String;
   function To_String (Item : UString) return String renames US.To_String;

   type Source_Position is record
      Line   : Positive := 1;
      Column : Positive := 1;
   end record;

   type Source_Span is record
      Start_Pos : Source_Position := (Line => 1, Column => 1);
      End_Pos   : Source_Position := (Line => 1, Column => 1);
   end record;

   Null_Span : constant Source_Span :=
     (Start_Pos => (Line => 1, Column => 1),
      End_Pos   => (Line => 1, Column => 1));

   package UString_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => UString,
      "="          => US."=");

   function Image (Item : Positive) return String;
   function Lowercase (Item : String) return String;
   function Span_Image (Span : Source_Span) return String;
end Safe_Frontend.Types;
