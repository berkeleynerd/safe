with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Mir_Diagnostics;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Types;

package Safe_Frontend.Mir_Bronze is
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
      Channels : FT.UString_Vectors.Vector;
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

   type Bronze_Result is record
      Graphs       : Graph_Summary_Vectors.Vector;
      Initializes  : FT.UString_Vectors.Vector;
      Ownership    : Ownership_Vectors.Vector;
      Ceilings     : Ceiling_Vectors.Vector;
      Diagnostics  : MD.Diagnostic_Vectors.Vector;
   end record;

   function Summarize
     (Document    : GM.Mir_Document;
      Path_String : String := "") return Bronze_Result;
end Safe_Frontend.Mir_Bronze;
