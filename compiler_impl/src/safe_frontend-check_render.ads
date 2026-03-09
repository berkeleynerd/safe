with Safe_Frontend.Mir_Diagnostics;

package Safe_Frontend.Check_Render is
   package MD renames Safe_Frontend.Mir_Diagnostics;

   function Render
     (Diagnostic  : MD.Diagnostic;
      Source_Text : String;
      Path        : String) return String;

   function Render
     (Diagnostics : MD.Diagnostic_Vectors.Vector;
      Source_Text : String;
      Path        : String) return String;
end Safe_Frontend.Check_Render;
