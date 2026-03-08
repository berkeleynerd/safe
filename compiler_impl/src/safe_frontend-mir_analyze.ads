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
     (Document : Safe_Frontend.Mir_Model.Mir_Document) return Analyze_Result;
end Safe_Frontend.Mir_Analyze;
