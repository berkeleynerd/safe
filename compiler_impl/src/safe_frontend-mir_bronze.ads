with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Check_Model;
with Safe_Frontend.Mir_Diagnostics;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Types;

package Safe_Frontend.Mir_Bronze is
   package CM renames Safe_Frontend.Check_Model;
   package FT renames Safe_Frontend.Types;
   package GM renames Safe_Frontend.Mir_Model;
   package MD renames Safe_Frontend.Mir_Diagnostics;

   type Depends_Entry is record
      Output_Name : FT.UString := FT.To_UString ("");
      Inputs      : FT.UString_Vectors.Vector;
   end record;

   package Depends_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Depends_Entry);

   type Graph_Summary is record
      Name     : FT.UString := FT.To_UString ("");
      Kind     : FT.UString := FT.To_UString ("");
      Reads    : FT.UString_Vectors.Vector;
      Writes   : FT.UString_Vectors.Vector;
      Shareds  : FT.UString_Vectors.Vector;
      Channels : FT.UString_Vectors.Vector;
      Sends    : FT.UString_Vectors.Vector;
      Receives : FT.UString_Vectors.Vector;
      Calls    : FT.UString_Vectors.Vector;
      Inputs   : FT.UString_Vectors.Vector;
      Outputs  : FT.UString_Vectors.Vector;
      Depends  : Depends_Vectors.Vector;
      Is_Task  : Boolean := False;
      Priority : Long_Long_Integer := 0;
   end record;

   package Graph_Summary_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Graph_Summary);

   type Ownership_Entry is record
      Global_Name : FT.UString := FT.To_UString ("");
      Task_Name   : FT.UString := FT.To_UString ("");
   end record;

   package Ownership_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Ownership_Entry);

   type Ceiling_Entry is record
      Channel_Name : FT.UString := FT.To_UString ("");
      Priority     : Long_Long_Integer := 0;
      Task_Names   : FT.UString_Vectors.Vector;
   end record;

   package Ceiling_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Ceiling_Entry);

   type Shared_Ceiling_Entry is record
      Shared_Name : FT.UString := FT.To_UString ("");
      Priority    : Long_Long_Integer := 0;
      Task_Names  : FT.UString_Vectors.Vector;
   end record;

   package Shared_Ceiling_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Shared_Ceiling_Entry);

   type Bronze_Result is record
      Graphs          : Graph_Summary_Vectors.Vector;
      Initializes     : FT.UString_Vectors.Vector;
      Ownership       : Ownership_Vectors.Vector;
      Ceilings        : Ceiling_Vectors.Vector;
      Shared_Ceilings : Shared_Ceiling_Vectors.Vector;
      Diagnostics     : MD.Diagnostic_Vectors.Vector;
   end record;

   function Summarize
     (Document    : GM.Mir_Document;
      Tasks       : CM.Resolved_Task_Vectors.Vector := CM.Resolved_Task_Vectors.Empty_Vector;
      Path_String : String := "";
      Objects     : CM.Resolved_Object_Decl_Vectors.Vector := CM.Resolved_Object_Decl_Vectors.Empty_Vector;
      Imported_Objects : CM.Imported_Object_Decl_Vectors.Vector := CM.Imported_Object_Decl_Vectors.Empty_Vector)
      return Bronze_Result;
end Safe_Frontend.Mir_Bronze;
