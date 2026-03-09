with Safe_Frontend.Check_Model;
with Safe_Frontend.Mir_Model;

package Safe_Frontend.Check_Lower is
   package CM renames Safe_Frontend.Check_Model;
   package GM renames Safe_Frontend.Mir_Model;

   function Lower (Unit : CM.Resolved_Unit) return GM.Mir_Document;
end Safe_Frontend.Check_Lower;
