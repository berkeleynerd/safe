with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Safe_Frontend;
with Safe_Frontend.Driver;

procedure Safec is
   function Usage return Integer is
   begin
      Ada.Text_IO.Put_Line ("usage:");
      Ada.Text_IO.Put_Line ("  safec lex <file.safe>");
      Ada.Text_IO.Put_Line ("  safec validate-mir <file.mir.json>");
      Ada.Text_IO.Put_Line ("  safec analyze-mir <file.mir.json>");
      Ada.Text_IO.Put_Line ("  safec analyze-mir --diag-json <file.mir.json>");
      Ada.Text_IO.Put_Line ("  safec ast <file.safe>");
      Ada.Text_IO.Put_Line ("  safec check <file.safe>");
      Ada.Text_IO.Put_Line ("  safec check --diag-json <file.safe>");
      Ada.Text_IO.Put_Line
        ("  safec emit <file.safe> --out-dir <dir> --interface-dir <dir>");
      return Safe_Frontend.Exit_Usage;
   end Usage;

   function Argument (Index : Positive) return String is
   begin
      return Ada.Command_Line.Argument (Index);
   end Argument;

   function Find_Option (Name : String) return Natural is
   begin
      for Index in 1 .. Ada.Command_Line.Argument_Count loop
         if Ada.Command_Line.Argument (Index) = Name then
            return Index;
         end if;
      end loop;
      return 0;
   end Find_Option;

   Exit_Code : Integer := Safe_Frontend.Exit_Usage;
begin
   if Ada.Command_Line.Argument_Count < 2 then
      Exit_Code := Usage;
      GNAT.OS_Lib.OS_Exit (Exit_Code);
   end if;

   declare
      Command : constant String := Argument (1);
   begin
      if Command = "lex" and then Ada.Command_Line.Argument_Count = 2 then
         Exit_Code := Safe_Frontend.Driver.Run_Lex (Argument (2));
      elsif Command = "validate-mir"
        and then Ada.Command_Line.Argument_Count = 2
      then
         Exit_Code := Safe_Frontend.Driver.Run_Validate_Mir (Argument (2));
      elsif Command = "analyze-mir" then
         if Ada.Command_Line.Argument_Count = 2 then
            Exit_Code := Safe_Frontend.Driver.Run_Analyze_Mir (Argument (2));
         elsif Ada.Command_Line.Argument_Count = 3
           and then Argument (2) = "--diag-json"
         then
            Exit_Code :=
              Safe_Frontend.Driver.Run_Analyze_Mir
                (Path      => Argument (3),
                 Diag_Json => True);
         else
            Exit_Code := Usage;
         end if;
      elsif Command = "ast" and then Ada.Command_Line.Argument_Count = 2 then
         Exit_Code := Safe_Frontend.Driver.Run_Ast (Argument (2));
      elsif Command = "check" then
         if Ada.Command_Line.Argument_Count = 2 then
            Exit_Code := Safe_Frontend.Driver.Run_Check (Argument (2));
         elsif Ada.Command_Line.Argument_Count = 3
           and then Argument (2) = "--diag-json"
         then
            Exit_Code :=
              Safe_Frontend.Driver.Run_Check
                (Path      => Argument (3),
                 Diag_Json => True);
         else
            Exit_Code := Usage;
         end if;
      elsif Command = "emit" then
         declare
            Out_Arg       : constant Natural := Find_Option ("--out-dir");
            Interface_Arg : constant Natural := Find_Option ("--interface-dir");
         begin
            if Ada.Command_Line.Argument_Count < 6
              or else Out_Arg = 0
              or else Interface_Arg = 0
              or else Out_Arg >= Ada.Command_Line.Argument_Count
              or else Interface_Arg >= Ada.Command_Line.Argument_Count
            then
               Exit_Code := Usage;
            else
               Exit_Code :=
                 Safe_Frontend.Driver.Run_Emit
                   (Path          => Argument (2),
                    Out_Dir       => Argument (Positive (Out_Arg + 1)),
                    Interface_Dir => Argument (Positive (Interface_Arg + 1)));
            end if;
         end;
      else
         Exit_Code := Usage;
      end if;
   end;

   GNAT.OS_Lib.OS_Exit (Exit_Code);
end Safec;
