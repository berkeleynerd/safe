with Safe_Frontend.Check_Model;

package Safe_Frontend.Check_Resolve is
   package CM renames Safe_Frontend.Check_Model;

   function Resolve (Unit : CM.Parsed_Unit) return CM.Resolve_Result;
end Safe_Frontend.Check_Resolve;
