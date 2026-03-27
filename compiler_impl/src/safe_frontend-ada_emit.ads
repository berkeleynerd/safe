with Safe_Frontend.Check_Model;
with Safe_Frontend.Mir_Bronze;
with Safe_Frontend.Mir_Diagnostics;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Types;

package Safe_Frontend.Ada_Emit is
   package CM renames Safe_Frontend.Check_Model;
   package FT renames Safe_Frontend.Types;
   package GM renames Safe_Frontend.Mir_Model;
   package MB renames Safe_Frontend.Mir_Bronze;
   package MD renames Safe_Frontend.Mir_Diagnostics;

   type Artifact_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Unit_Name           : FT.UString := FT.To_UString ("");
            Spec_Text           : FT.UString := FT.To_UString ("");
            Body_Text           : FT.UString := FT.To_UString ("");
            Needs_Safe_IO       : Boolean := False;
            Needs_Safe_Runtime  : Boolean := False;
            Needs_Gnat_Adc      : Boolean := False;
         when False =>
            Diagnostic : MD.Diagnostic;
      end case;
   end record;

   function Emit
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result) return Artifact_Result;

   function Safe_Runtime_Text return String;
   function Safe_IO_Spec_Text return String;
   function Safe_IO_Body_Text return String;
   function Gnat_Adc_Text return String;
   function Unit_File_Stem (Unit_Name : String) return String;
end Safe_Frontend.Ada_Emit;
