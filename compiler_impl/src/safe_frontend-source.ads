with Safe_Frontend.Types;

package Safe_Frontend.Source is
   package FT renames Safe_Frontend.Types;

   type Source_File is record
      Path    : FT.UString := FT.To_UString ("");
      Content : FT.UString := FT.To_UString ("");
   end record;

   function Load (Path : String) return Source_File;
end Safe_Frontend.Source;
