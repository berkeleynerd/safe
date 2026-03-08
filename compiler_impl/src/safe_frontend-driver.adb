with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Command_Line;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Safe_Frontend.Ast;
with Safe_Frontend.Check_Lower;
with Safe_Frontend.Check_Parse;
with Safe_Frontend.Check_Render;
with Safe_Frontend.Check_Resolve;
with Safe_Frontend.Diagnostics;
with Safe_Frontend.Lexer;
with Safe_Frontend.Mir;
with Safe_Frontend.Mir_Analyze;
with Safe_Frontend.Mir_Diagnostics;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Mir_Validate;
with Safe_Frontend.Parser;
with Safe_Frontend.Semantics;
with Safe_Frontend.Source;
with Safe_Frontend.Types;

package body Safe_Frontend.Driver is
   package CL renames Safe_Frontend.Check_Lower;
   package CP renames Safe_Frontend.Check_Parse;
   package CR renames Safe_Frontend.Check_Render;
   package CS renames Safe_Frontend.Check_Resolve;
   package FD renames Safe_Frontend.Diagnostics;
   package FL renames Safe_Frontend.Lexer;
   package FM renames Safe_Frontend.Mir;
   package MD renames Safe_Frontend.Mir_Diagnostics;
   package FP renames Safe_Frontend.Parser;
   package FS renames Safe_Frontend.Source;
   package FT renames Safe_Frontend.Types;
   type Lex_Result is record
      Input       : FS.Source_File;
      Tokens      : FL.Token_Vectors.Vector;
      Diagnostics : FD.Diagnostic_Vectors.Vector;
      Internal_Failure : Boolean := False;
      Success     : Boolean := False;
   end record;

   type Pipeline_Result is record
      Ast         : Safe_Frontend.Ast.Compilation_Unit;
      Typed       : Safe_Frontend.Semantics.Typed_Unit;
      Mir_Unit    : FM.Unit;
      Diagnostics : FD.Diagnostic_Vectors.Vector;
      Internal_Failure : Boolean := False;
      Success     : Boolean := False;
   end record;

   function Full_Command_Name return String is
      use type GNAT.OS_Lib.String_Access;
      Raw : constant String := Ada.Command_Line.Command_Name;
   begin
      if Ada.Directories.Exists (Raw) then
         return Ada.Directories.Full_Name (Raw);
      end if;
      declare
         Located : GNAT.OS_Lib.String_Access :=
           GNAT.OS_Lib.Locate_Exec_On_Path (Raw);
      begin
         if Located /= null then
            declare
               Result : constant String := Located.all;
            begin
               GNAT.OS_Lib.Free (Located);
               return Result;
            end;
         end if;
      end;
      return Raw;
   end Full_Command_Name;

   function Backend_Script return String is
      Command_Path  : constant String := Full_Command_Name;
      Bin_Dir       : constant String := Ada.Directories.Containing_Directory (Command_Path);
      Compiler_Root : constant String := Ada.Directories.Containing_Directory (Bin_Dir);
      Candidate     : constant String := Compiler_Root & "/backend/pr05_backend.py";
   begin
      if Ada.Directories.Exists (Candidate) then
         return Candidate;
      end if;
      return "compiler_impl/backend/pr05_backend.py";
   end Backend_Script;

   function Python3 return String is
      use type GNAT.OS_Lib.String_Access;
      Located : GNAT.OS_Lib.String_Access :=
        GNAT.OS_Lib.Locate_Exec_On_Path ("python3");
   begin
      if Located /= null then
         declare
            Result : constant String := Located.all;
         begin
            GNAT.OS_Lib.Free (Located);
            return Result;
         end;
      end if;
      return "python3";
   end Python3;

   function Run_Backend
     (Command       : String;
      Path          : String;
      Diag_Json     : Boolean := False;
      Out_Dir       : String := "";
      Interface_Dir : String := "") return Integer
   is
      use type GNAT.OS_Lib.String_Access;

      Arg_Count : constant Positive :=
        (if Command = "emit" then 9
         elsif Diag_Json then 6
         else 5);
      Args      : GNAT.OS_Lib.Argument_List (1 .. Arg_Count);
      Last      : Natural := 0;

      procedure Push (Value : String) is
      begin
         Last := Last + 1;
         Args (Last) := new String'(Value);
      end Push;

      procedure Free_Args is
      begin
         for Index in Args'Range loop
            if Args (Index) /= null then
               GNAT.OS_Lib.Free (Args (Index));
            end if;
         end loop;
      end Free_Args;
   begin
      Push (Backend_Script);
      Push (Command);
      Push (Path);
      Push ("--safec-binary");
      Push (Full_Command_Name);
      if Diag_Json then
         Push ("--diag-json");
      end if;
      if Command = "emit" then
         Push ("--out-dir");
         Push (Out_Dir);
         Push ("--interface-dir");
         Push (Interface_Dir);
      end if;
      declare
         Result : constant Integer := GNAT.OS_Lib.Spawn (Python3, Args);
      begin
         Free_Args;
         return Result;
      end;
   exception
      when others =>
         Free_Args;
         raise;
   end Run_Backend;

   function Source_Stem (Path : String) return String is
      Simple : constant String := Ada.Directories.Simple_Name (Path);
      Dot    : constant Natural := Ada.Strings.Fixed.Index (Simple, ".", Ada.Strings.Backward);
   begin
      if Dot = 0 then
         return Ada.Characters.Handling.To_Lower (Simple);
      end if;
      return
        Ada.Characters.Handling.To_Lower
          (Simple (Simple'First .. Dot - 1));
   end Source_Stem;

   procedure Write_File (Path : String; Contents : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File => File, Mode => Ada.Text_IO.Out_File, Name => Path);
      Ada.Text_IO.Put (File, Contents);
      Ada.Text_IO.Close (File);
   end Write_File;

   function Failure_Exit_Code (Result : Pipeline_Result) return Integer is
   begin
      if Result.Internal_Failure then
         return Safe_Frontend.Exit_Internal;
      end if;
      return Safe_Frontend.Exit_Diagnostics;
   end Failure_Exit_Code;

   function Failure_Exit_Code (Result : Lex_Result) return Integer is
   begin
      if Result.Internal_Failure then
         return Safe_Frontend.Exit_Internal;
      end if;
      return Safe_Frontend.Exit_Diagnostics;
   end Failure_Exit_Code;

   function To_Source_Reason
     (Code    : String;
      Message : String) return String is
   begin
      if Code in "SC3002" | "SC3003"
        or else Ada.Strings.Fixed.Index
          (FT.Lowercase (Message), "unsupported") /= 0
      then
         return "unsupported_source_construct";
      end if;
      return "source_frontend_error";
   end To_Source_Reason;

   function To_Mir_Diagnostic
     (Item         : FD.Diagnostic;
      Default_Path : String) return MD.Diagnostic
   is
      Result : MD.Diagnostic;
      Path   : constant String :=
        (if FT.To_String (Item.Path)'Length > 0
         then FT.To_String (Item.Path)
         else Default_Path);
   begin
      Result.Reason :=
        FT.To_UString
          (To_Source_Reason
             (FT.To_String (Item.Code),
              FT.To_String (Item.Message)));
      Result.Message := Item.Message;
      Result.Path := FT.To_UString (Path);
      Result.Span := Item.Span;
      if FT.To_String (Item.Note)'Length > 0 then
         Result.Notes.Append (Item.Note);
      end if;
      if FT.To_String (Item.Suggestion)'Length > 0 then
         Result.Suggestions.Append (Item.Suggestion);
      end if;
      return Result;
   end To_Mir_Diagnostic;

   function To_Mir_Diagnostics
     (Items        : FD.Diagnostic_Vectors.Vector;
      Default_Path : String) return MD.Diagnostic_Vectors.Vector
   is
      Result : MD.Diagnostic_Vectors.Vector;
   begin
      if not Items.Is_Empty then
         Result.Append (To_Mir_Diagnostic (Items (Items.First_Index), Default_Path));
      end if;
      return Result;
   end To_Mir_Diagnostics;

   function Singleton
     (Item : MD.Diagnostic) return MD.Diagnostic_Vectors.Vector
   is
      Result : MD.Diagnostic_Vectors.Vector;
   begin
      Result.Append (Item);
      return Result;
   end Singleton;

   function Render_Check_Diagnostics
     (Diagnostics : MD.Diagnostic_Vectors.Vector;
      Source_Text : String;
      Path        : String) return String is
   begin
      return CR.Render (Diagnostics, Source_Text, Path);
   end Render_Check_Diagnostics;

   function Emit_Check_Diagnostics
     (Diagnostics : MD.Diagnostic_Vectors.Vector;
      Source_Text : String;
      Path        : String;
      Diag_Json   : Boolean) return Integer is
   begin
      if Diag_Json then
         Ada.Text_IO.Put (MD.To_Json (Diagnostics));
      else
         Ada.Text_IO.Put
           (Ada.Text_IO.Current_Error,
            Render_Check_Diagnostics (Diagnostics, Source_Text, Path));
      end if;
      return Safe_Frontend.Exit_Diagnostics;
   end Emit_Check_Diagnostics;

   function Run_Lexing (Path : String) return Lex_Result is
      Result : Lex_Result;
   begin
      Result.Input := FS.Load (Path);
      Result.Tokens := FL.Lex (Result.Input, Result.Diagnostics);
      Result.Success := not FD.Has_Errors (Result.Diagnostics);
      return Result;
   exception
      when Ada.IO_Exceptions.Name_Error =>
         FD.Add_Error
           (Collection => Result.Diagnostics,
            Path       => Path,
            Span       => FT.Null_Span,
            Code       => "SC0001",
            Message    => "input file not found",
            Note       => "could not open `" & Path & "`");
         return Result;
      when Ada.IO_Exceptions.Use_Error =>
         FD.Add_Error
           (Collection => Result.Diagnostics,
            Path       => Path,
            Span       => FT.Null_Span,
            Code       => "SC0002",
            Message    => "input file could not be read",
            Note       => "could not read `" & Path & "`");
         return Result;
      when Error : others =>
         Result.Internal_Failure := True;
         FD.Add_Error
           (Collection => Result.Diagnostics,
            Path       => Path,
            Span       => FT.Null_Span,
            Code       => "SC9001",
            Message    => "internal compiler error",
            Note       =>
              Ada.Exceptions.Exception_Name (Error)
              & ": "
              & Ada.Exceptions.Exception_Message (Error));
         return Result;
   end Run_Lexing;

   function Run_Pipeline (Path : String; Include_Semantics : Boolean := True) return Pipeline_Result is
      Result : Pipeline_Result;
      Lexed  : constant Lex_Result := Run_Lexing (Path);
   begin
      Result.Diagnostics := Lexed.Diagnostics;
      Result.Internal_Failure := Lexed.Internal_Failure;
      if not Lexed.Success then
         return Result;
      end if;

      Result.Ast := FP.Parse (Lexed.Input, Lexed.Tokens, Result.Diagnostics);
      if FD.Has_Errors (Result.Diagnostics) or else not Include_Semantics then
         Result.Success := not FD.Has_Errors (Result.Diagnostics);
         return Result;
      end if;
      Result.Typed :=
        Safe_Frontend.Semantics.Analyze
          (Result.Ast, Lexed.Tokens, Result.Diagnostics);
      if FD.Has_Errors (Result.Diagnostics) then
         return Result;
      end if;
      Result.Mir_Unit := FM.Lower (Result.Typed);
      Result.Success := True;
      return Result;
   end Run_Pipeline;

   function Run_Lex (Path : String) return Integer is
      Result : constant Lex_Result := Run_Lexing (Path);
   begin
      if not Result.Success then
         FD.Print (Result.Diagnostics);
         return Failure_Exit_Code (Result);
      end if;
      Ada.Text_IO.Put (FL.To_Json (Result.Tokens));
      return Safe_Frontend.Exit_Success;
   end Run_Lex;

   function Run_Validate_Mir (Path : String) return Integer is
      Result : constant Safe_Frontend.Mir_Model.Validation_Result :=
        Safe_Frontend.Mir_Validate.Validate_File (Path);
   begin
      if Result.Success then
         Ada.Text_IO.Put_Line ("validate-mir: OK (" & Path & ")");
         return Safe_Frontend.Exit_Success;
      end if;

      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Current_Error,
         "validate-mir: ERROR: "
         & Safe_Frontend.Types.To_String (Result.Message));
      return Safe_Frontend.Exit_Diagnostics;
   exception
      when Error : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Current_Error,
            "validate-mir: ERROR: internal failure: "
            & Ada.Exceptions.Exception_Name (Error)
            & ": "
            & Ada.Exceptions.Exception_Message (Error));
         return Safe_Frontend.Exit_Internal;
   end Run_Validate_Mir;

   function Run_Analyze_Mir
     (Path      : String;
      Diag_Json : Boolean := False) return Integer
   is
      package MD renames Safe_Frontend.Mir_Diagnostics;

      Result : constant Safe_Frontend.Mir_Analyze.Analyze_Result :=
        Safe_Frontend.Mir_Analyze.Analyze_File (Path);
   begin
      if not Result.Success then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Current_Error,
            "analyze-mir: ERROR: " & Safe_Frontend.Types.To_String (Result.Message));
         return Safe_Frontend.Exit_Diagnostics;
      elsif Diag_Json then
         Ada.Text_IO.Put (MD.To_Json (Result.Diagnostics));
      elsif Result.Diagnostics.Is_Empty then
         Ada.Text_IO.Put_Line ("analyze-mir: OK (" & Path & ")");
      else
         declare
            Diag : constant MD.Diagnostic := Result.Diagnostics (Result.Diagnostics.First_Index);
         begin
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Current_Error,
               "analyze-mir: ERROR: "
               & Safe_Frontend.Types.To_String (Diag.Path)
               & ":"
               & FT.Image (Diag.Span.Start_Pos.Line)
               & ":"
               & FT.Image (Diag.Span.Start_Pos.Column)
               & ": "
               & Safe_Frontend.Types.To_String (Diag.Message));
         end;
      end if;
      if Result.Diagnostics.Is_Empty then
         return Safe_Frontend.Exit_Success;
      end if;
      return Safe_Frontend.Exit_Diagnostics;
   exception
      when Error : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Current_Error,
            "analyze-mir: ERROR: internal failure: "
            & Ada.Exceptions.Exception_Name (Error)
            & ": "
            & Ada.Exceptions.Exception_Message (Error));
         return Safe_Frontend.Exit_Internal;
   end Run_Analyze_Mir;

   function Run_Ast (Path : String) return Integer is
   begin
      return Run_Backend ("ast", Path);
   end Run_Ast;

   function Run_Check
     (Path      : String;
      Diag_Json : Boolean := False) return Integer
   is
      Lexed       : Lex_Result;
      Diagnostics : MD.Diagnostic_Vectors.Vector;
   begin
      Lexed := Run_Lexing (Path);
      if not Lexed.Success then
         if Lexed.Internal_Failure then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Current_Error,
               "check: ERROR: internal failure while loading or lexing `" & Path & "`");
            return Safe_Frontend.Exit_Internal;
         end if;
         Diagnostics := To_Mir_Diagnostics (Lexed.Diagnostics, Path);
         return
           Emit_Check_Diagnostics
             (Diagnostics,
              FT.To_String (Lexed.Input.Content),
              Path,
              Diag_Json);
      end if;

      declare
         Parsed : constant CP.CM.Parse_Result :=
           CP.Parse (Lexed.Input, Lexed.Tokens);
      begin
         if not Parsed.Success then
            return
              Emit_Check_Diagnostics
                (Singleton (Parsed.Diagnostic),
                 FT.To_String (Lexed.Input.Content),
                 Path,
                 Diag_Json);
         end if;

         declare
            Resolved : constant CS.CM.Resolve_Result := CS.Resolve (Parsed.Unit);
         begin
            if not Resolved.Success then
               return
                 Emit_Check_Diagnostics
                   (Singleton (Resolved.Diagnostic),
                    FT.To_String (Lexed.Input.Content),
                    Path,
                    Diag_Json);
            end if;

            declare
               Mir_Result : constant Safe_Frontend.Mir_Analyze.Analyze_Result :=
                 Safe_Frontend.Mir_Analyze.Analyze (CL.Lower (Resolved.Unit));
            begin
               if not Mir_Result.Success then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Current_Error,
                     "check: ERROR: internal failure: "
                     & FT.To_String (Mir_Result.Message));
                  return Safe_Frontend.Exit_Internal;
               elsif Diag_Json then
                  Ada.Text_IO.Put (MD.To_Json (Mir_Result.Diagnostics));
               elsif not Mir_Result.Diagnostics.Is_Empty then
                  Ada.Text_IO.Put
                    (Ada.Text_IO.Current_Error,
                     Render_Check_Diagnostics
                       (Mir_Result.Diagnostics,
                        FT.To_String (Lexed.Input.Content),
                        Path));
               end if;

               if Mir_Result.Diagnostics.Is_Empty then
                  return Safe_Frontend.Exit_Success;
               end if;
               return Safe_Frontend.Exit_Diagnostics;
            end;
         end;
      end;
   exception
      when Error : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Current_Error,
            "check: ERROR: internal failure: "
            & Ada.Exceptions.Exception_Name (Error)
            & ": "
            & Ada.Exceptions.Exception_Message (Error));
         return Safe_Frontend.Exit_Internal;
   end Run_Check;

   function Run_Emit
     (Path          : String;
      Out_Dir       : String;
      Interface_Dir : String) return Integer
   is
   begin
      return Run_Backend
        (Command       => "emit",
         Path          => Path,
         Out_Dir       => Out_Dir,
         Interface_Dir => Interface_Dir);
   end Run_Emit;
end Safe_Frontend.Driver;
