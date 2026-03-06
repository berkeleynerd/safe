with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;
with Safe_Frontend.Json;

package body Safe_Frontend.Mir is
   package FS renames Safe_Frontend.Semantics;
   package US renames Ada.Strings.Unbounded;

   function Lower (Typed : FS.Typed_Unit) return Unit is
      Result : Unit := (Package_Name => Typed.Ast.Package_Name, others => <>);
   begin
      if Typed.Executables.Is_Empty then
         declare
            Graph_Item : Graph;
            Entry_Block : Block;
            Exit_Block : Block;
         begin
            Graph_Item.Name := FT.To_UString ("package_elaboration");
            Graph_Item.Kind := FT.To_UString ("Package");
            Graph_Item.Entry_Label := FT.To_UString ("entry");
            Graph_Item.Exit_Label := FT.To_UString ("exit");
            Graph_Item.Span := Typed.Ast.Span;
            Entry_Block.Label := FT.To_UString ("entry");
            Entry_Block.Statements.Append
              (FT.To_UString
                 ("elaborate package " & FT.To_String (Typed.Ast.Package_Name)));
            Entry_Block.Successors.Append (FT.To_UString ("exit"));
            Entry_Block.Span := Typed.Ast.Span;
            Exit_Block.Label := FT.To_UString ("exit");
            Exit_Block.Span := Typed.Ast.Span;
            Graph_Item.Blocks.Append (Entry_Block);
            Graph_Item.Blocks.Append (Exit_Block);
            Result.Graphs.Append (Graph_Item);
         end;
      else
         for Exec of Typed.Executables loop
            declare
               Graph_Item : Graph;
               Entry_Block : Block;
               Exit_Block : Block;
            begin
               Graph_Item.Name := Exec.Name;
               Graph_Item.Kind := Exec.Kind;
               Graph_Item.Entry_Label := FT.To_UString ("entry");
               Graph_Item.Exit_Label := FT.To_UString ("exit");
               Graph_Item.Span := Exec.Span;
               Entry_Block.Label := FT.To_UString ("entry");
               Entry_Block.Statements.Append
                 (FT.To_UString
                    ("enter "
                     & FT.To_String (Exec.Kind)
                     & " "
                     & FT.To_String (Exec.Name)));
               Entry_Block.Successors.Append (FT.To_UString ("exit"));
               Entry_Block.Span := Exec.Span;
               Exit_Block.Label := FT.To_UString ("exit");
               Exit_Block.Span := Exec.Span;
               Graph_Item.Blocks.Append (Entry_Block);
               Graph_Item.Blocks.Append (Exit_Block);
               Result.Graphs.Append (Graph_Item);
            end;
         end loop;
      end if;
      return Result;
   end Lower;

   function To_Json (Mir_Unit : Unit) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      US.Append (Result, "{");
      US.Append (Result, """format"":""mir-v0"",");
      US.Append (Result, """package_name"":" & Safe_Frontend.Json.Quote (Mir_Unit.Package_Name) & ",");
      US.Append (Result, """graphs"":[");
      if not Mir_Unit.Graphs.Is_Empty then
         for Graph_Index in Mir_Unit.Graphs.First_Index .. Mir_Unit.Graphs.Last_Index loop
            declare
               Graph_Item : constant Graph := Mir_Unit.Graphs.Element (Graph_Index);
            begin
               if Graph_Index > Mir_Unit.Graphs.First_Index then
                  US.Append (Result, ",");
               end if;
               US.Append
                 (Result,
                  "{""name"":" & Safe_Frontend.Json.Quote (Graph_Item.Name)
                  & ",""kind"":" & Safe_Frontend.Json.Quote (Graph_Item.Kind)
                  & ",""entry_label"":" & Safe_Frontend.Json.Quote (Graph_Item.Entry_Label)
                  & ",""exit_label"":" & Safe_Frontend.Json.Quote (Graph_Item.Exit_Label)
                  & ",""span"":" & Safe_Frontend.Json.Span_Object (Graph_Item.Span)
                  & ",""blocks"":[");
               if not Graph_Item.Blocks.Is_Empty then
                  for Block_Index in Graph_Item.Blocks.First_Index .. Graph_Item.Blocks.Last_Index loop
                     declare
                        Block_Item : constant Block := Graph_Item.Blocks.Element (Block_Index);
                     begin
                        if Block_Index > Graph_Item.Blocks.First_Index then
                           US.Append (Result, ",");
                        end if;
                        US.Append
                          (Result,
                           "{""label"":" & Safe_Frontend.Json.Quote (Block_Item.Label)
                           & ",""statements"":[");
                        if not Block_Item.Statements.Is_Empty then
                           for Statement_Index in Block_Item.Statements.First_Index .. Block_Item.Statements.Last_Index loop
                              if Statement_Index > Block_Item.Statements.First_Index then
                                 US.Append (Result, ",");
                              end if;
                              US.Append (Result, Safe_Frontend.Json.Quote (Block_Item.Statements.Element (Statement_Index)));
                           end loop;
                        end if;
                        US.Append (Result, "],""successors"":[");
                        if not Block_Item.Successors.Is_Empty then
                           for Successor_Index in Block_Item.Successors.First_Index .. Block_Item.Successors.Last_Index loop
                              if Successor_Index > Block_Item.Successors.First_Index then
                                 US.Append (Result, ",");
                              end if;
                              US.Append (Result, Safe_Frontend.Json.Quote (Block_Item.Successors.Element (Successor_Index)));
                           end loop;
                        end if;
                        US.Append
                          (Result,
                           "],""span"":" & Safe_Frontend.Json.Span_Object (Block_Item.Span) & "}");
                     end;
                  end loop;
               end if;
               US.Append (Result, "]}");
            end;
         end loop;
      end if;
      US.Append (Result, "]}");
      return US.To_String (Result) & Ada.Characters.Latin_1.LF;
   end To_Json;
end Safe_Frontend.Mir;
