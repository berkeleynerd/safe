with Safe_Frontend.Check_Model;
with Safe_Frontend.Mir_Diagnostics;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Types;

package Safe_Frontend.Mir_Analyze is
   package FT renames Safe_Frontend.Types;
   package MD renames Safe_Frontend.Mir_Diagnostics;

   type Analyze_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Diagnostics : MD.Diagnostic_Vectors.Vector;
         when False =>
            Message : FT.UString;
      end case;
   end record;

   function Analyze_File (Path : String) return Analyze_Result;
   function Analyze
     (Document : Safe_Frontend.Mir_Model.Mir_Document;
      Tasks    : Safe_Frontend.Check_Model.Resolved_Task_Vectors.Vector :=
        Safe_Frontend.Check_Model.Resolved_Task_Vectors.Empty_Vector;
      Objects : Safe_Frontend.Check_Model.Resolved_Object_Decl_Vectors.Vector :=
        Safe_Frontend.Check_Model.Resolved_Object_Decl_Vectors.Empty_Vector;
      Imported_Objects : Safe_Frontend.Check_Model.Imported_Object_Decl_Vectors.Vector :=
        Safe_Frontend.Check_Model.Imported_Object_Decl_Vectors.Empty_Vector) return Analyze_Result;
end Safe_Frontend.Mir_Analyze;
