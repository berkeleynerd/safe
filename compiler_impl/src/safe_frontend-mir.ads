with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Semantics;
with Safe_Frontend.Types;

package Safe_Frontend.Mir is
   package FT renames Safe_Frontend.Types;

   type Block is record
      Label      : FT.UString := FT.To_UString ("");
      Statements : FT.UString_Vectors.Vector;
      Successors : FT.UString_Vectors.Vector;
      Span       : FT.Source_Span := FT.Null_Span;
   end record;

   package Block_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Block);

   type Graph is record
      Name        : FT.UString := FT.To_UString ("");
      Kind        : FT.UString := FT.To_UString ("");
      Entry_Label : FT.UString := FT.To_UString ("");
      Exit_Label  : FT.UString := FT.To_UString ("");
      Span        : FT.Source_Span := FT.Null_Span;
      Blocks      : Block_Vectors.Vector;
   end record;

   package Graph_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Graph);

   type Unit is record
      Package_Name : FT.UString := FT.To_UString ("");
      Graphs       : Graph_Vectors.Vector;
   end record;

   function Lower (Typed : Safe_Frontend.Semantics.Typed_Unit) return Unit;
   function To_Json (Mir_Unit : Unit) return String;
end Safe_Frontend.Mir;
