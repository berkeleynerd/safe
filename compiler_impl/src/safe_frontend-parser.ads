with Safe_Frontend.Ast;
with Safe_Frontend.Diagnostics;
with Safe_Frontend.Lexer;
with Safe_Frontend.Source;

package Safe_Frontend.Parser is
   function Parse
     (Input       : Safe_Frontend.Source.Source_File;
      Tokens      : Safe_Frontend.Lexer.Token_Vectors.Vector;
      Diagnostics :
        aliased in out Safe_Frontend.Diagnostics.Diagnostic_Vectors.Vector)
      return Safe_Frontend.Ast.Compilation_Unit;
end Safe_Frontend.Parser;
