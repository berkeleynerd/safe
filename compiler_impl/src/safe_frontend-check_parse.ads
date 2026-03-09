with Safe_Frontend.Check_Model;
with Safe_Frontend.Lexer;
with Safe_Frontend.Source;

package Safe_Frontend.Check_Parse is
   package CM renames Safe_Frontend.Check_Model;

   function Parse
     (Input  : Safe_Frontend.Source.Source_File;
      Tokens : Safe_Frontend.Lexer.Token_Vectors.Vector) return CM.Parse_Result;
end Safe_Frontend.Check_Parse;
