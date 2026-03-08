with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Types;

package Safe_Frontend.Mir_Diagnostics is
   package FT renames Safe_Frontend.Types;

   type Diagnostic is record
      Reason             : FT.UString := FT.To_UString ("");
      Message            : FT.UString := FT.To_UString ("");
      Path               : FT.UString := FT.To_UString ("");
      Span               : FT.Source_Span := FT.Null_Span;
      Has_Highlight_Span : Boolean := False;
      Highlight_Span     : FT.Source_Span := FT.Null_Span;
      Notes              : FT.UString_Vectors.Vector;
      Suggestions        : FT.UString_Vectors.Vector;
      Sequence           : Natural := 0;
   end record;

   package Diagnostic_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Diagnostic);

   function To_Json
     (Diagnostics : Diagnostic_Vectors.Vector) return String;
end Safe_Frontend.Mir_Diagnostics;
