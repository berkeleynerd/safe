with Safe_Frontend.Types;

package Safe_Frontend.Name_Utils is
   package FT renames Safe_Frontend.Types;

   function Sanitize_Type_Name_Component (Value : String) return String;
   function Sanitize_Type_Name_Component_Trimmed (Value : String) return String;
   function Sanitize_Type_Name_Component_Raw (Value : String) return String;
end Safe_Frontend.Name_Utils;
