with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Types;

package Safe_Frontend.Diagnostics is
   package FT renames Safe_Frontend.Types;

   type Diagnostic_Severity is (Error_Severity, Note_Severity);

   type Diagnostic is record
      Path       : FT.UString := FT.To_UString ("");
      Span       : FT.Source_Span := FT.Null_Span;
      Severity   : Diagnostic_Severity := Error_Severity;
      Code       : FT.UString := FT.To_UString ("");
      Message    : FT.UString := FT.To_UString ("");
      Note       : FT.UString := FT.To_UString ("");
      Suggestion : FT.UString := FT.To_UString ("");
   end record;

   package Diagnostic_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Diagnostic);

   procedure Add_Error
     (Collection : in out Diagnostic_Vectors.Vector;
      Path       : String;
      Span       : FT.Source_Span;
      Code       : String;
      Message    : String;
      Note       : String := "";
      Suggestion : String := "");

   function Has_Errors (Collection : Diagnostic_Vectors.Vector) return Boolean;
   function Format (Collection : Diagnostic_Vectors.Vector) return String;
   procedure Print (Collection : Diagnostic_Vectors.Vector);
end Safe_Frontend.Diagnostics;
