with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Types;

package Safe_Frontend.Ast is
   package FT renames Safe_Frontend.Types;

   type Package_Item_Kind is
     (Type_Declaration,
      Subtype_Declaration,
      Object_Declaration,
      Number_Declaration,
      Subprogram_Declaration,
      Task_Declaration,
      Channel_Declaration,
      Use_Type_Clause,
      Pragma_Item,
      Representation_Item,
      Unknown_Item);

   type With_Clause is record
      Package_Names : FT.UString_Vectors.Vector;
      Span          : FT.Source_Span := FT.Null_Span;
   end record;

   package With_Clause_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => With_Clause);

   type Package_Item is record
      Kind          : Package_Item_Kind := Unknown_Item;
      Is_Public     : Boolean := False;
      Name          : FT.UString := FT.To_UString ("");
      Span          : FT.Source_Span := FT.Null_Span;
      Header_Text   : FT.UString := FT.To_UString ("");
      Signature     : FT.UString := FT.To_UString ("");
      Has_Body      : Boolean := False;
      Element_Type  : FT.UString := FT.To_UString ("");
      Capacity_Text : FT.UString := FT.To_UString ("");
      Return_Type   : FT.UString := FT.To_UString ("");
   end record;

   package Package_Item_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Package_Item);

   type Compilation_Unit is record
      Package_Name : FT.UString := FT.To_UString ("");
      End_Name     : FT.UString := FT.To_UString ("");
      With_Clauses : With_Clause_Vectors.Vector;
      Items        : Package_Item_Vectors.Vector;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   function Kind_Name (Kind : Package_Item_Kind) return String;
   function To_Json (Unit : Compilation_Unit) return String;
end Safe_Frontend.Ast;
