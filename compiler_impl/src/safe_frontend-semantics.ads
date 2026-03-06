with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Ast;
with Safe_Frontend.Diagnostics;
with Safe_Frontend.Lexer;
with Safe_Frontend.Types;

package Safe_Frontend.Semantics is
   package FT renames Safe_Frontend.Types;

   type Declaration_Summary is record
      Name      : FT.UString := FT.To_UString ("");
      Kind      : FT.UString := FT.To_UString ("");
      Signature : FT.UString := FT.To_UString ("");
      Span      : FT.Source_Span := FT.Null_Span;
   end record;

   package Declaration_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Declaration_Summary);

   type Executable_Summary is record
      Name      : FT.UString := FT.To_UString ("");
      Kind      : FT.UString := FT.To_UString ("");
      Signature : FT.UString := FT.To_UString ("");
      Span      : FT.Source_Span := FT.Null_Span;
   end record;

   package Executable_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Executable_Summary);

   type Typed_Unit is record
      Ast                 : Safe_Frontend.Ast.Compilation_Unit;
      Public_Declarations : Declaration_Vectors.Vector;
      Executables         : Executable_Vectors.Vector;
   end record;

   function Analyze
     (Unit        : Safe_Frontend.Ast.Compilation_Unit;
      Tokens      : Safe_Frontend.Lexer.Token_Vectors.Vector;
      Diagnostics : in out Safe_Frontend.Diagnostics.Diagnostic_Vectors.Vector)
      return Typed_Unit;

   function To_Json (Unit : Typed_Unit) return String;
   function Interface_Json (Unit : Typed_Unit) return String;
end Safe_Frontend.Semantics;
