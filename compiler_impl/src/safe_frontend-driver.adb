with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Safe_Frontend.Ada_Emit;
with Safe_Frontend.Check_Emit;
with Safe_Frontend.Check_Lower;
with Safe_Frontend.Check_Parse;
with Safe_Frontend.Check_Render;
with Safe_Frontend.Check_Resolve;
with Safe_Frontend.Diagnostics;
with Safe_Frontend.Lexer;
with Safe_Frontend.Mir_Analyze;
with Safe_Frontend.Mir_Bronze;
with Safe_Frontend.Mir_Diagnostics;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Mir_Validate;
with Safe_Frontend.Mir_Write;
with Safe_Frontend.Source;

package body Safe_Frontend.Driver is
   package AE renames Safe_Frontend.Ada_Emit;
   package CE renames Safe_Frontend.Check_Emit;
   package CL renames Safe_Frontend.Check_Lower;
   package CP renames Safe_Frontend.Check_Parse;
   package CR renames Safe_Frontend.Check_Render;
   package CS renames Safe_Frontend.Check_Resolve;
   package FD renames Safe_Frontend.Diagnostics;
   package FL renames Safe_Frontend.Lexer;
   package MB renames Safe_Frontend.Mir_Bronze;
   package MD renames Safe_Frontend.Mir_Diagnostics;
   package FS renames Safe_Frontend.Source;
   use type CP.CM.Unit_Kind;
   type Lex_Result is record
      Input       : FS.Source_File;
      Tokens      : FL.Token_Vectors.Vector;
      Diagnostics : FD.Diagnostic_Vectors.Vector;
      Internal_Failure : Boolean := False;
      Success     : Boolean := False;
   end record;

   type Source_Result (Success : Boolean := False) is record
      Lexed : Lex_Result;
      case Success is
         when True =>
            Parsed   : CP.CM.Parsed_Unit;
            Resolved : CS.CM.Resolved_Unit;
         when False =>
            Diagnostic : MD.Diagnostic;
      end case;
   end record;

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

   function Main_Text (Unit_Name : String) return String is
   begin
      return
        "with "
        & Unit_Name
        & ";"
        & ASCII.LF
        & ASCII.LF
        & "procedure Main is"
        & ASCII.LF
        & "begin"
        & ASCII.LF
        & "   null;"
        & ASCII.LF
        & "end Main;"
        & ASCII.LF;
   end Main_Text;

   procedure Write_File (Path : String; Contents : String) is
      package AS renames Ada.Streams;
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      --  Emit exact bytes so generated artifacts match the committed
      --  snapshots/templates without text-mode newline translation.
      SIO.Create (File => File, Mode => SIO.Out_File, Name => Path);
      if Contents'Length > 0 then
         declare
            Data : AS.Stream_Element_Array
              (1 .. AS.Stream_Element_Offset (Contents'Length));
         begin
            for Index in Contents'Range loop
               Data (AS.Stream_Element_Offset (Index - Contents'First + 1)) :=
                 AS.Stream_Element (Character'Pos (Contents (Index)));
            end loop;
            SIO.Write (File, Data);
         end;
      end if;
      SIO.Close (File);
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Write_File;

   procedure Best_Effort_Delete (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>
         null;
   end Best_Effort_Delete;

   procedure Write_Shared_Support_File
     (Path     : String;
      Contents : String) is
      Temp_Path   : constant String := Path & ".safec-tmp";
      Backup_Path : constant String := Path & ".safec-bak";
      Had_Target  : constant Boolean := Ada.Directories.Exists (Path);
   begin
      Best_Effort_Delete (Temp_Path);
      Best_Effort_Delete (Backup_Path);

      Write_File (Temp_Path, Contents);

      if Had_Target then
         Ada.Directories.Rename (Old_Name => Path, New_Name => Backup_Path);
      end if;

      begin
         Ada.Directories.Rename (Old_Name => Temp_Path, New_Name => Path);
      exception
         when others =>
            Best_Effort_Delete (Temp_Path);
            if Had_Target and then Ada.Directories.Exists (Backup_Path) then
               begin
                  Ada.Directories.Rename (Old_Name => Backup_Path, New_Name => Path);
               exception
                  when others =>
                     null;
               end;
            end if;
            raise;
      end;

      Best_Effort_Delete (Backup_Path);
   exception
      when others =>
         Best_Effort_Delete (Temp_Path);
         raise;
   end Write_Shared_Support_File;

   procedure Delete_If_Exists
     (Path           : String;
      Cleanup_Failed : in out Boolean) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when Ada.IO_Exceptions.Name_Error =>
         null;
      when others =>
         Cleanup_Failed := True;
   end Delete_If_Exists;

   procedure Cleanup_Ada_Artifacts
     (Ada_Out_Dir : String;
      Ada_Stem    : String;
      Has_Main    : Boolean;
      Cleanup_Failed : in out Boolean) is
   begin
      Delete_If_Exists
        (Ada_Out_Dir & "/" & Ada_Stem & ".ads",
         Cleanup_Failed);
      Delete_If_Exists
        (Ada_Out_Dir & "/" & Ada_Stem & ".adb",
         Cleanup_Failed);
      if Has_Main then
         Delete_If_Exists
           (Ada_Out_Dir & "/main.adb",
            Cleanup_Failed);
      end if;
   end Cleanup_Ada_Artifacts;

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
         for Index in Items.First_Index .. Items.Last_Index loop
            Result.Append (To_Mir_Diagnostic (Items (Index), Default_Path));
         end loop;
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

   function Run_Source_Pipeline
     (Path        : String;
      Search_Dirs : FT.UString_Vectors.Vector := FT.UString_Vectors.Empty_Vector;
      Target_Bits : Positive := 64)
      return Source_Result
   is
      Lexed : constant Lex_Result := Run_Lexing (Path);
   begin
      if not Lexed.Success then
         return (Success => False, Lexed => Lexed, Diagnostic => <>);
      end if;

      declare
         Parsed : constant CP.CM.Parse_Result := CP.Parse (Lexed.Input, Lexed.Tokens);
      begin
         if not Parsed.Success then
            return
              (Success    => False,
               Lexed      => Lexed,
               Diagnostic => Parsed.Diagnostic);
         end if;

         declare
            Resolved : constant CS.CM.Resolve_Result :=
              CS.Resolve (Parsed.Unit, Search_Dirs, Target_Bits);
         begin
            if not Resolved.Success then
               return
                 (Success    => False,
                  Lexed      => Lexed,
                  Diagnostic => Resolved.Diagnostic);
            end if;

            return
              (Success  => True,
               Lexed    => Lexed,
               Parsed   => Parsed.Unit,
               Resolved => Resolved.Unit);
         end;
      end;
   end Run_Source_Pipeline;

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

   function Run_Ast
     (Path        : String;
      Search_Dirs : FT.UString_Vectors.Vector := FT.UString_Vectors.Empty_Vector;
      Target_Bits : Positive := 64)
      return Integer
   is
      Result : constant Source_Result := Run_Source_Pipeline (Path, Search_Dirs, Target_Bits);
   begin
      if not Result.Lexed.Success then
         FD.Print (Result.Lexed.Diagnostics);
         return Failure_Exit_Code (Result.Lexed);
      elsif not Result.Success then
         return
           Emit_Check_Diagnostics
             (Singleton (Result.Diagnostic),
              FT.To_String (Result.Lexed.Input.Content),
              Path,
              False);
      end if;

      Ada.Text_IO.Put (CE.Ast_Json (Result.Parsed, Result.Resolved));
      return Safe_Frontend.Exit_Success;
   exception
      when Error : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Current_Error,
            "ast: ERROR: internal failure: "
            & Ada.Exceptions.Exception_Name (Error)
            & ": "
            & Ada.Exceptions.Exception_Message (Error));
         return Safe_Frontend.Exit_Internal;
   end Run_Ast;

   function Run_Check
     (Path        : String;
      Diag_Json   : Boolean := False;
      Search_Dirs : FT.UString_Vectors.Vector := FT.UString_Vectors.Empty_Vector;
      Target_Bits : Positive := 64)
      return Integer
   is
      Pipeline    : Source_Result;
      Diagnostics : MD.Diagnostic_Vectors.Vector;
   begin
      Pipeline := Run_Source_Pipeline (Path, Search_Dirs, Target_Bits);
      if not Pipeline.Lexed.Success then
         if Pipeline.Lexed.Internal_Failure then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Current_Error,
               "check: ERROR: internal failure while loading or lexing `" & Path & "`");
            return Safe_Frontend.Exit_Internal;
         end if;
         Diagnostics := To_Mir_Diagnostics (Pipeline.Lexed.Diagnostics, Path);
         return
           Emit_Check_Diagnostics
             (Diagnostics,
              FT.To_String (Pipeline.Lexed.Input.Content),
              Path,
              Diag_Json);
      end if;

      if not Pipeline.Success then
         return
           Emit_Check_Diagnostics
             (Singleton (Pipeline.Diagnostic),
              FT.To_String (Pipeline.Lexed.Input.Content),
              Path,
              Diag_Json);
      end if;

      declare
         Mir_Result : constant Safe_Frontend.Mir_Analyze.Analyze_Result :=
           Safe_Frontend.Mir_Analyze.Analyze
             (CL.Lower (Pipeline.Resolved),
              Pipeline.Resolved.Tasks,
              Pipeline.Resolved.Objects,
              Pipeline.Resolved.Imported_Objects);
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
                  FT.To_String (Pipeline.Lexed.Input.Content),
                  Path));
         end if;

         if Mir_Result.Diagnostics.Is_Empty then
            return Safe_Frontend.Exit_Success;
         end if;
         return Safe_Frontend.Exit_Diagnostics;
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
      Interface_Dir : String;
      Ada_Out_Dir   : String := "";
      Search_Dirs   : FT.UString_Vectors.Vector := FT.UString_Vectors.Empty_Vector;
      Target_Bits   : Positive := 64)
      return Integer
   is
      Pipeline : constant Source_Result := Run_Source_Pipeline (Path, Search_Dirs, Target_Bits);
   begin
      if not Pipeline.Lexed.Success then
         FD.Print (Pipeline.Lexed.Diagnostics);
         return Failure_Exit_Code (Pipeline.Lexed);
      elsif not Pipeline.Success then
         return
           Emit_Check_Diagnostics
             (Singleton (Pipeline.Diagnostic),
              FT.To_String (Pipeline.Lexed.Input.Content),
              Path,
              False);
      end if;

      declare
         Mir_Doc    : constant Safe_Frontend.Mir_Model.Mir_Document :=
           CL.Lower (Pipeline.Resolved);
         Bronze     : constant MB.Bronze_Result :=
           MB.Summarize
             (Mir_Doc,
              Pipeline.Resolved.Tasks,
              Path,
              Pipeline.Resolved.Objects,
              Pipeline.Resolved.Imported_Objects);
         Mir_Result : constant Safe_Frontend.Mir_Analyze.Analyze_Result :=
           Safe_Frontend.Mir_Analyze.Analyze
             (Mir_Doc,
              Pipeline.Resolved.Tasks,
              Pipeline.Resolved.Objects,
              Pipeline.Resolved.Imported_Objects);
         Stem       : constant String := Source_Stem (Path);
         Ast_Text   : constant String := CE.Ast_Json (Pipeline.Parsed, Pipeline.Resolved);
         Typed_Text : constant String := CE.Typed_Json (Pipeline.Parsed, Pipeline.Resolved);
         Mir_Text   : constant String := Safe_Frontend.Mir_Write.To_Json (Mir_Doc);
         Safei_Text : constant String := CE.Interface_Json (Pipeline.Parsed, Pipeline.Resolved, Bronze);
      begin
         if not Mir_Result.Success then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Current_Error,
               "emit: ERROR: internal failure: "
               & FT.To_String (Mir_Result.Message));
            return Safe_Frontend.Exit_Internal;
         elsif not Mir_Result.Diagnostics.Is_Empty then
            Ada.Text_IO.Put
              (Ada.Text_IO.Current_Error,
               Render_Check_Diagnostics
                 (Mir_Result.Diagnostics,
                  FT.To_String (Pipeline.Lexed.Input.Content),
                  Path));
            return Safe_Frontend.Exit_Diagnostics;
         end if;

         declare
            Ada_Result : constant AE.Artifact_Result :=
              (if Ada_Out_Dir'Length > 0
               then AE.Emit (Pipeline.Resolved, Mir_Doc, Bronze)
               else (Success => True,
                     Unit_Name => FT.To_UString (""),
                     Spec_Text => FT.To_UString (""),
                     Body_Text => FT.To_UString (""),
                     Needs_Gnat_Adc => False));
            Gnat_Adc     : constant String :=
              (if Ada_Out_Dir'Length > 0 and then Ada_Result.Success and then Ada_Result.Needs_Gnat_Adc
               then AE.Gnat_Adc_Text
               else "");
            Entry_Main   : constant String :=
              (if Ada_Out_Dir'Length > 0
                  and then Ada_Result.Success
                  and then Pipeline.Resolved.Kind = CP.CM.Unit_Entry
               then Main_Text (FT.To_String (Ada_Result.Unit_Name))
               else "");
         begin
            if not Ada_Result.Success then
               return
                 Emit_Check_Diagnostics
                   (Singleton (Ada_Result.Diagnostic),
                    FT.To_String (Pipeline.Lexed.Input.Content),
                    Path,
                    False);
            end if;

            Ada.Directories.Create_Path (Out_Dir);
            Ada.Directories.Create_Path (Interface_Dir);
            if Ada_Out_Dir'Length > 0 then
               Ada.Directories.Create_Path (Ada_Out_Dir);
            end if;
            Write_File
              (Out_Dir & "/" & Stem & ".ast.json",
               Ast_Text);
            Write_File
              (Out_Dir & "/" & Stem & ".typed.json",
               Typed_Text);
            Write_File
              (Out_Dir & "/" & Stem & ".mir.json",
               Mir_Text);
            Write_File
              (Interface_Dir & "/" & Stem & ".safei.json",
               Safei_Text);
            if Ada_Out_Dir'Length > 0 then
               declare
                  Ada_Stem : constant String := AE.Unit_File_Stem (FT.To_String (Ada_Result.Unit_Name));
               begin
                  begin
                     Write_File
                       (Ada_Out_Dir & "/" & Ada_Stem & ".ads",
                        FT.To_String (Ada_Result.Spec_Text));
                     Write_File
                       (Ada_Out_Dir & "/" & Ada_Stem & ".adb",
                        FT.To_String (Ada_Result.Body_Text));
                     if Pipeline.Resolved.Kind = CP.CM.Unit_Entry then
                        Write_File
                          (Ada_Out_Dir & "/main.adb",
                           Entry_Main);
                     end if;
                     if Ada_Result.Needs_Gnat_Adc then
                        Write_Shared_Support_File
                          (Ada_Out_Dir & "/gnat.adc",
                           Gnat_Adc);
                     end if;
                  exception
                     when others =>
                        declare
                           Cleanup_Failed : Boolean := False;
                        begin
                           Cleanup_Ada_Artifacts
                             (Ada_Out_Dir,
                              Ada_Stem,
                              Pipeline.Resolved.Kind = CP.CM.Unit_Entry,
                              Cleanup_Failed);
                           if Cleanup_Failed then
                              Ada.Text_IO.Put_Line
                                (Ada.Text_IO.Current_Error,
                                 "emit: WARNING: failed to remove one or more partially written Ada artifacts from `"
                                 & Ada_Out_Dir
                                 & "`");
                           end if;
                        end;
                        raise;
                  end;
               end;
            end if;
            return Safe_Frontend.Exit_Success;
         end;
      end;
   exception
      when Error : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Current_Error,
            "emit: ERROR: internal failure: "
            & Ada.Exceptions.Exception_Name (Error)
            & ": "
            & Ada.Exceptions.Exception_Message (Error));
         return Safe_Frontend.Exit_Internal;
   end Run_Emit;
end Safe_Frontend.Driver;
