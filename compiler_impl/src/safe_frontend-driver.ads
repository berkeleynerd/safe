package Safe_Frontend.Driver is
   function Run_Lex (Path : String) return Integer;
   function Run_Validate_Mir (Path : String) return Integer;
   function Run_Analyze_Mir
     (Path      : String;
      Diag_Json : Boolean := False) return Integer;
   function Run_Ast (Path : String) return Integer;
   function Run_Check
     (Path      : String;
      Diag_Json : Boolean := False) return Integer;
   function Run_Emit
     (Path          : String;
      Out_Dir       : String;
      Interface_Dir : String) return Integer;
end Safe_Frontend.Driver;
