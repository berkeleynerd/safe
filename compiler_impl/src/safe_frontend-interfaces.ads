with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Check_Model;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Types;

package Safe_Frontend.Interfaces is
   package CM renames Safe_Frontend.Check_Model;
   package FT renames Safe_Frontend.Types;
   package GM renames Safe_Frontend.Mir_Model;

   type Imported_Object is record
      Name         : FT.UString := FT.To_UString ("");
      Type_Info    : GM.Type_Descriptor;
      Is_Shared    : Boolean := False;
      Is_Constant  : Boolean := False;
      Static_Info  : CM.Static_Value;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   package Imported_Object_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Imported_Object);

   type Imported_Subprogram is record
      Name                 : FT.UString := FT.To_UString ("");
      Kind                 : FT.UString := FT.To_UString ("");
      Signature            : FT.UString := FT.To_UString ("");
      Params               : CM.Symbol_Vectors.Vector;
      Has_Return_Type      : Boolean := False;
      Return_Type          : GM.Type_Descriptor;
      Return_Is_Access_Def : Boolean := False;
      Generic_Formals      : GM.Generic_Formal_Descriptor_Vectors.Vector;
      Has_Template_Source  : Boolean := False;
      Template_Source      : FT.UString := FT.To_UString ("");
      Span                 : FT.Source_Span := FT.Null_Span;
      Effect_Summary       : GM.External_Effect_Summary;
      Channel_Summary      : GM.External_Channel_Summary;
   end record;

   package Imported_Subprogram_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Imported_Subprogram);

   type Loaded_Interface is record
      Unit_Kind    : FT.UString := FT.To_UString ("package");
      Target_Bits  : Positive := 64;
      Package_Name : FT.UString := FT.To_UString ("");
      Types        : GM.Type_Descriptor_Vectors.Vector;
      Subtypes     : GM.Type_Descriptor_Vectors.Vector;
      Channels     : CM.Resolved_Channel_Decl_Vectors.Vector;
      Objects      : Imported_Object_Vectors.Vector;
      Subprograms  : Imported_Subprogram_Vectors.Vector;
   end record;

   package Loaded_Interface_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Loaded_Interface);

   type Load_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Interfaces : Loaded_Interface_Vectors.Vector;
         when False =>
            Diagnostic : CM.MD.Diagnostic;
      end case;
   end record;

   function Load_Dependencies
     (Search_Dirs : FT.UString_Vectors.Vector;
      Withs       : CM.With_Clause_Vectors.Vector;
      Path        : String) return Load_Result;
end Safe_Frontend.Interfaces;
