with Ada.Containers;
with Safe_Frontend.Ada_Emit.Expressions;
with Safe_Frontend.Ada_Emit.Statements;
with Safe_Frontend.Ada_Emit.Types;

package body Safe_Frontend.Ada_Emit.Proofs is
   use AI;

   package AET renames Safe_Frontend.Ada_Emit.Types;
   package AEX renames Safe_Frontend.Ada_Emit.Expressions;
   package AES renames Safe_Frontend.Ada_Emit.Statements;
   use AET;
   use AEX;
   use AES;

   use type Ada.Containers.Count_Type;
   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Statement_Access;
   use type CM.Statement_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Select_Arm_Kind;
   use type FT.UString;
   use type GM.Scalar_Value_Kind;

   function Render_Subprogram_Params
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Params     : CM.Symbol_Vectors.Vector) return String
   is
      Result : SU.Unbounded_String := SU.To_Unbounded_String ("(");
   begin
      if Params.Is_Empty then
         return "";
      end if;

      for Index in Params.First_Index .. Params.Last_Index loop
         declare
            Param : constant CM.Symbol := Params (Index);
            Mode  : constant String := FT.To_String (Param.Mode);
         begin
            if Index /= Params.First_Index then
               Result := Result & SU.To_Unbounded_String ("; ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (FT.To_String (Param.Name)
                   & " : "
                  & (if Mode = "" or else Mode = "borrow"
                      then "in "
                      elsif Mode = "mut"
                      then "in out "
                      elsif Mode = "in"
                      then "in "
                      else Mode & " ")
                   & Render_Param_Type_Name (Unit, Document, Param.Type_Info));
         end;
      end loop;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Subprogram_Params;
   function Render_Subprogram_Return
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram) return String is
   begin
      if Subprogram.Has_Return_Type then
         return
           " return "
           & Render_Subtype_Indication (Unit, Document, Subprogram.Return_Type);
      end if;
      return "";
   end Render_Subprogram_Return;
   function Render_Ada_Subprogram_Keyword
     (Subprogram : CM.Resolved_Subprogram) return String is
   begin
      if Subprogram.Has_Return_Type then
         return "function";
      end if;
      return "procedure";
   end Render_Ada_Subprogram_Keyword;
   function Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector
   is
      Result : CM.Resolved_Object_Decl_Vectors.Vector;
   begin
      for Decl of Declarations loop
         if Is_Alias_Access (Decl.Type_Info) then
            Result.Append (Decl);
         end if;
      end loop;
      return Result;
   end Alias_Declarations;
   function Non_Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector
   is
      Result : CM.Resolved_Object_Decl_Vectors.Vector;
   begin
      for Decl of Declarations loop
         if not Is_Alias_Access (Decl.Type_Info) then
            Result.Append (Decl);
         end if;
      end loop;
      return Result;
   end Non_Alias_Declarations;
   procedure Render_In_Out_Param_Stabilizers
     (Buffer     : in out SU.Unbounded_String;
      Subprogram : CM.Resolved_Subprogram;
      Depth      : Natural)
   is
      --  Intentionally left as a no-op. The pre-split emitter also called
      --  this stub without emitting stabilizers; keep that behavior until
      --  stabilizer generation is explicitly scoped.
      pragma Unreferenced (Buffer, Subprogram, Depth);
   begin
      null;
   end Render_In_Out_Param_Stabilizers;
   function Find_Graph_Summary
     (Bronze : MB.Bronze_Result;
      Name   : String) return MB.Graph_Summary
   is
   begin
      for Item of Bronze.Graphs loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Find_Graph_Summary;
   function Subprogram_Uses_Global_Name
     (Unit       : CM.Resolved_Unit;
      Subprogram : CM.Resolved_Subprogram;
      Name       : String) return Boolean
   is
      procedure Collect_Call_Names_From_Expr
        (Expr  : CM.Expr_Access;
         Calls : in out FT.UString_Vectors.Vector);

      procedure Collect_Call_Names_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector;
         Calls      : in out FT.UString_Vectors.Vector);

      function Subprogram_Mentions_Name
        (Item_Subprogram : CM.Resolved_Subprogram;
         Visited_Calls   : in out FT.UString_Vectors.Vector) return Boolean;

      function Called_Subprograms_Mention_Name
        (Item_Subprogram : CM.Resolved_Subprogram;
         Visited_Calls   : in out FT.UString_Vectors.Vector) return Boolean;

      procedure Add_Call_Name
        (Calls : in out FT.UString_Vectors.Vector;
         Name  : String) is
      begin
         if Name'Length > 0 and then not Contains_Name (Calls, Name) then
            Calls.Append (FT.To_UString (Name));
         end if;
      end Add_Call_Name;

      procedure Collect_Call_Names_From_Expr
        (Expr  : CM.Expr_Access;
         Calls : in out FT.UString_Vectors.Vector)
      is
      begin
         if Expr = null then
            return;
         end if;

         if Expr.Kind = CM.Expr_Call and then Expr.Callee /= null then
            Add_Call_Name (Calls, FT.Lowercase (CM.Flatten_Name (Expr.Callee)));
         end if;

         Collect_Call_Names_From_Expr (Expr.Prefix, Calls);
         Collect_Call_Names_From_Expr (Expr.Callee, Calls);
         Collect_Call_Names_From_Expr (Expr.Inner, Calls);
         Collect_Call_Names_From_Expr (Expr.Left, Calls);
         Collect_Call_Names_From_Expr (Expr.Right, Calls);
         Collect_Call_Names_From_Expr (Expr.Value, Calls);
         Collect_Call_Names_From_Expr (Expr.Target, Calls);
         for Arg of Expr.Args loop
            Collect_Call_Names_From_Expr (Arg, Calls);
         end loop;
         for Field of Expr.Fields loop
            Collect_Call_Names_From_Expr (Field.Expr, Calls);
         end loop;
         for Element of Expr.Elements loop
            Collect_Call_Names_From_Expr (Element, Calls);
         end loop;
      end Collect_Call_Names_From_Expr;

      procedure Collect_Call_Names_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector;
         Calls      : in out FT.UString_Vectors.Vector)
      is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Object_Decl =>
                     Collect_Call_Names_From_Expr (Item.Decl.Initializer, Calls);
                  when CM.Stmt_Destructure_Decl =>
                     Collect_Call_Names_From_Expr (Item.Destructure.Initializer, Calls);
                  when CM.Stmt_Assign =>
                     Collect_Call_Names_From_Expr (Item.Target, Calls);
                     Collect_Call_Names_From_Expr (Item.Value, Calls);
                  when CM.Stmt_Call =>
                     Collect_Call_Names_From_Expr (Item.Call, Calls);
                  when CM.Stmt_Return =>
                     Collect_Call_Names_From_Expr (Item.Value, Calls);
                  when CM.Stmt_If =>
                     Collect_Call_Names_From_Expr (Item.Condition, Calls);
                     Collect_Call_Names_From_Statements (Item.Then_Stmts, Calls);
                     for Part of Item.Elsifs loop
                        Collect_Call_Names_From_Expr (Part.Condition, Calls);
                        Collect_Call_Names_From_Statements (Part.Statements, Calls);
                     end loop;
                     if Item.Has_Else then
                        Collect_Call_Names_From_Statements (Item.Else_Stmts, Calls);
                     end if;
                  when CM.Stmt_Case =>
                     Collect_Call_Names_From_Expr (Item.Case_Expr, Calls);
                     for Arm of Item.Case_Arms loop
                        Collect_Call_Names_From_Expr (Arm.Choice, Calls);
                        Collect_Call_Names_From_Statements (Arm.Statements, Calls);
                     end loop;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     Collect_Call_Names_From_Expr (Item.Condition, Calls);
                     Collect_Call_Names_From_Expr (Item.Loop_Range.Name_Expr, Calls);
                     Collect_Call_Names_From_Expr (Item.Loop_Range.Low_Expr, Calls);
                     Collect_Call_Names_From_Expr (Item.Loop_Range.High_Expr, Calls);
                     Collect_Call_Names_From_Expr (Item.Loop_Iterable, Calls);
                     Collect_Call_Names_From_Statements (Item.Body_Stmts, Calls);
                  when CM.Stmt_Send =>
                     Collect_Call_Names_From_Expr (Item.Channel_Name, Calls);
                     Collect_Call_Names_From_Expr (Item.Value, Calls);
                     Collect_Call_Names_From_Expr (Item.Success_Var, Calls);
                  when CM.Stmt_Receive =>
                     Collect_Call_Names_From_Expr (Item.Channel_Name, Calls);
                     Collect_Call_Names_From_Expr (Item.Target, Calls);
                  when CM.Stmt_Try_Send =>
                     Raise_Internal ("unreachable: try_send rejected by resolver");
                  when CM.Stmt_Try_Receive =>
                     Collect_Call_Names_From_Expr (Item.Channel_Name, Calls);
                     Collect_Call_Names_From_Expr (Item.Target, Calls);
                     Collect_Call_Names_From_Expr (Item.Success_Var, Calls);
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Collect_Call_Names_From_Expr (Arm.Channel_Data.Channel_Name, Calls);
                              Collect_Call_Names_From_Statements (Arm.Channel_Data.Statements, Calls);
                           when CM.Select_Arm_Delay =>
                              Collect_Call_Names_From_Expr (Arm.Delay_Data.Duration_Expr, Calls);
                              Collect_Call_Names_From_Statements (Arm.Delay_Data.Statements, Calls);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when CM.Stmt_Delay =>
                     Collect_Call_Names_From_Expr (Item.Value, Calls);
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Collect_Call_Names_From_Statements;

      function Called_Subprograms_Mention_Name
        (Item_Subprogram : CM.Resolved_Subprogram;
         Visited_Calls   : in out FT.UString_Vectors.Vector) return Boolean
      is
         Calls : FT.UString_Vectors.Vector;
      begin
         for Decl of Item_Subprogram.Declarations loop
            Collect_Call_Names_From_Expr (Decl.Initializer, Calls);
         end loop;
         Collect_Call_Names_From_Statements (Item_Subprogram.Statements, Calls);

         for Called of Calls loop
            declare
               Called_Name : constant String := FT.Lowercase (FT.To_String (Called));
            begin
               if Called_Name'Length = 0 then
                  null;
               else
                  for Candidate of Unit.Subprograms loop
                     declare
                        Candidate_Name : constant String := FT.Lowercase (FT.To_String (Candidate.Name));
                        Qualified_Candidate_Name : constant String :=
                          FT.Lowercase (FT.To_String (Unit.Package_Name) & "." & FT.To_String (Candidate.Name));
                     begin
                        if Called_Name = Candidate_Name
                          or else Called_Name = Qualified_Candidate_Name
                        then
                           if not Contains_Name (Visited_Calls, Candidate_Name) then
                              Visited_Calls.Append (FT.To_UString (Candidate_Name));
                              if Subprogram_Mentions_Name (Candidate, Visited_Calls) then
                                 return True;
                              end if;
                           end if;
                           exit;
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end loop;

         return False;
      end Called_Subprograms_Mention_Name;
      function Subprogram_Mentions_Name
        (Item_Subprogram : CM.Resolved_Subprogram;
         Visited_Calls   : in out FT.UString_Vectors.Vector) return Boolean
      is
      begin
         for Decl of Item_Subprogram.Declarations loop
            if Expr_Uses_Name (Decl.Initializer, Name) then
               return True;
            end if;
         end loop;

         return
           Statements_Use_Name (Item_Subprogram.Statements, Name)
           or else Called_Subprograms_Mention_Name (Item_Subprogram, Visited_Calls);
      end Subprogram_Mentions_Name;
   begin
      if Name'Length = 0 then
         return False;
      end if;

      declare
         Visited_Calls : FT.UString_Vectors.Vector;
         Subprogram_Name : constant String := FT.Lowercase (FT.To_String (Subprogram.Name));
      begin
         if Subprogram_Name'Length > 0 then
            Visited_Calls.Append (FT.To_UString (Subprogram_Name));
         end if;
         return Subprogram_Mentions_Name (Subprogram, Visited_Calls);
      end;
   end Subprogram_Uses_Global_Name;
   function Render_Initializes_Aspect
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result) return String
   is
      pragma Unreferenced (Document);
      Items : FT.UString_Vectors.Vector;

      procedure Add_Unique (Name : String) is
      begin
         if Name'Length > 0 and then not Contains_Name (Items, Name) then
            Items.Append (FT.To_UString (Name));
         end if;
      end Add_Unique;
   begin
      for Item of Bronze.Initializes loop
         if Is_Aspect_State_Name (FT.To_String (Item))
           and then not Is_Constant_Object_Name (Unit, FT.To_String (Item))
         then
            Add_Unique (FT.To_String (Item));
         end if;
      end loop;

      for Channel of Unit.Channels loop
         Add_Unique (FT.To_String (Channel.Name));
      end loop;

      for Task_Item of Unit.Tasks loop
         Add_Unique (FT.To_String (Task_Item.Name));
      end loop;

      for Decl of Unit.Objects loop
         if not Decl.Is_Constant and then not Decl.Is_Shared then
            for Name of Decl.Names loop
               Add_Unique (FT.To_String (Name));
            end loop;
         elsif Decl.Is_Shared
           and then not Decl.Is_Public
           and then not Decl.Names.Is_Empty
         then
            Add_Unique
              (Shared_Wrapper_Object_Name
                 (FT.To_String (Decl.Names (Decl.Names.First_Index))));
         end if;
      end loop;

      if Items.Is_Empty then
         return "null";
      elsif Items.Length = 1 then
         return FT.To_String (Items (Items.First_Index));
      end if;
      return "(" & Join_Names (Items) & ")";
   end Render_Initializes_Aspect;
   function Render_Global_Aspect
     (Unit       : CM.Resolved_Unit;
      Subprogram : CM.Resolved_Subprogram;
      Summary    : MB.Graph_Summary;
      Bronze     : MB.Bronze_Result) return String
   is
      pragma Unreferenced (Bronze);
      Inputs  : FT.UString_Vectors.Vector;
      Outputs : FT.UString_Vectors.Vector;
      In_Outs : FT.UString_Vectors.Vector;

      function Contains
        (Items : FT.UString_Vectors.Vector;
         Name  : String) return Boolean is
      begin
         for Item of Items loop
            if FT.To_String (Item) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Contains;

      procedure Add_Unique
        (Items : in out FT.UString_Vectors.Vector;
         Name  : String) is
      begin
         if not Contains (Items, Name) then
            Items.Append (FT.To_UString (Name));
         end if;
      end Add_Unique;

      function Is_Shared_Wrapper_Name (Name : String) return Boolean is
      begin
         for Decl of Unit.Objects loop
            if Decl.Is_Shared and then not Decl.Names.Is_Empty then
               if Shared_Wrapper_Object_Name
                    (FT.To_String (Decl.Names (Decl.Names.First_Index))) = Name
               then
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end Is_Shared_Wrapper_Name;

      function Try_Shared_Public_Helper
        (Name         : String;
         Wrapper_Name : out FT.UString;
         Operation    : out FT.UString) return Boolean is
      begin
         Wrapper_Name := FT.To_UString ("");
         Operation := FT.To_UString ("");
         for Decl of Unit.Objects loop
            if Decl.Is_Shared
              and then Decl.Is_Public
              and then not Decl.Names.Is_Empty
            then
               declare
                  Root_Name    : constant String :=
                    FT.To_String (Decl.Names (Decl.Names.First_Index));
                  Candidate_Wrapper : constant String :=
                    Shared_Wrapper_Object_Name (Root_Name);
                  Prefix      : constant String :=
                    Shared_Public_Helper_Base_Name (Root_Name) & "_";
               begin
                  if Starts_With (Name, Prefix) and then Name'Length > Prefix'Length then
                     Wrapper_Name := FT.To_UString (Candidate_Wrapper);
                     Operation := FT.To_UString (Name (Prefix'Length + 1 .. Name'Last));
                     return True;
                  end if;
               end;
            end if;
         end loop;

         return False;
      end Try_Shared_Public_Helper;

      procedure Mark_Shared_Call
        (Wrapper_Name  : String;
         Selector_Name : String;
         Reads         : in out FT.UString_Vectors.Vector;
         Writes        : in out FT.UString_Vectors.Vector) is
      begin
         if Wrapper_Name'Length = 0 then
            return;
         end if;

         if Selector_Name = Shared_Pop_Last_Name
           or else Selector_Name = Shared_Remove_Name
         then
            Add_Unique (Reads, Wrapper_Name);
            Add_Unique (Writes, Wrapper_Name);
         elsif Selector_Name = Shared_Append_Name
           or else Selector_Name = Shared_Set_Name
           or else Selector_Name = "Initialize"
           or else Starts_With (Selector_Name, "Set_")
         then
            Add_Unique (Writes, Wrapper_Name);
         elsif Selector_Name = Shared_Contains_Name
           or else Starts_With (Selector_Name, "Get_")
         then
            Add_Unique (Reads, Wrapper_Name);
         end if;
      end Mark_Shared_Call;

      procedure Collect_Shared_From_Expr
        (Expr   : CM.Expr_Access;
         Reads  : in out FT.UString_Vectors.Vector;
         Writes : in out FT.UString_Vectors.Vector);
      procedure Collect_Shared_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector;
         Reads      : in out FT.UString_Vectors.Vector;
         Writes     : in out FT.UString_Vectors.Vector);

      procedure Collect_Shared_From_Expr
        (Expr   : CM.Expr_Access;
         Reads  : in out FT.UString_Vectors.Vector;
         Writes : in out FT.UString_Vectors.Vector)
      is
      begin
         if Expr = null then
            return;
         end if;

         case Expr.Kind is
            when CM.Expr_Ident =>
               declare
                  Name : constant String := FT.To_String (Expr.Name);
               begin
                  if Is_Shared_Wrapper_Name (Name) then
                     Add_Unique (Reads, Name);
                  end if;
               end;
            when CM.Expr_Select =>
               Collect_Shared_From_Expr (Expr.Prefix, Reads, Writes);
            when CM.Expr_Resolved_Index =>
               Collect_Shared_From_Expr (Expr.Prefix, Reads, Writes);
               for Arg of Expr.Args loop
                  Collect_Shared_From_Expr (Arg, Reads, Writes);
               end loop;
            when CM.Expr_Call =>
               if Expr.Callee /= null then
                  declare
                     Wrapper_Name  : FT.UString := FT.To_UString ("");
                     Selector_Name : FT.UString := FT.To_UString ("");
                  begin
                     if Expr.Callee.Kind = CM.Expr_Select
                       and then Expr.Callee.Prefix /= null
                       and then Expr.Callee.Prefix.Kind = CM.Expr_Ident
                       and then Is_Shared_Wrapper_Name
                         (FT.To_String (Expr.Callee.Prefix.Name))
                     then
                        Wrapper_Name := Expr.Callee.Prefix.Name;
                        Selector_Name := Expr.Callee.Selector;
                     elsif Expr.Callee.Kind = CM.Expr_Ident then
                        if Try_Shared_Public_Helper
                          (FT.To_String (Expr.Callee.Name),
                           Wrapper_Name,
                           Selector_Name)
                        then
                           null;
                        end if;
                     elsif Expr.Callee.Kind = CM.Expr_Select then
                        if Try_Shared_Public_Helper
                          (CM.Flatten_Name (Expr.Callee),
                           Wrapper_Name,
                           Selector_Name)
                        then
                           null;
                        end if;
                     end if;

                     if FT.To_String (Wrapper_Name)'Length > 0 then
                        Mark_Shared_Call
                          (FT.To_String (Wrapper_Name),
                           FT.To_String (Selector_Name),
                           Reads,
                           Writes);
                     end if;
                  end;
               end if;
               Collect_Shared_From_Expr (Expr.Prefix, Reads, Writes);
               Collect_Shared_From_Expr (Expr.Callee, Reads, Writes);
               for Arg of Expr.Args loop
                  Collect_Shared_From_Expr (Arg, Reads, Writes);
               end loop;
            when CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Unary =>
               Collect_Shared_From_Expr (Expr.Inner, Reads, Writes);
               Collect_Shared_From_Expr (Expr.Target, Reads, Writes);
            when CM.Expr_Binary =>
               Collect_Shared_From_Expr (Expr.Left, Reads, Writes);
               Collect_Shared_From_Expr (Expr.Right, Reads, Writes);
            when CM.Expr_Aggregate =>
               for Field of Expr.Fields loop
                  Collect_Shared_From_Expr (Field.Expr, Reads, Writes);
               end loop;
            when CM.Expr_Tuple | CM.Expr_Array_Literal =>
               for Item of Expr.Elements loop
                  Collect_Shared_From_Expr (Item, Reads, Writes);
               end loop;
            when others =>
               null;
         end case;
      end Collect_Shared_From_Expr;

      procedure Collect_Shared_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector;
         Reads      : in out FT.UString_Vectors.Vector;
         Writes     : in out FT.UString_Vectors.Vector)
      is
      begin
         for Item of Statements loop
            if Item /= null then
               case Item.Kind is
                  when CM.Stmt_Object_Decl =>
                     Collect_Shared_From_Expr (Item.Decl.Initializer, Reads, Writes);
                  when CM.Stmt_Destructure_Decl =>
                     Collect_Shared_From_Expr (Item.Destructure.Initializer, Reads, Writes);
                  when CM.Stmt_Assign =>
                     Collect_Shared_From_Expr (Item.Target, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Value, Reads, Writes);
                  when CM.Stmt_Call =>
                     Collect_Shared_From_Expr (Item.Call, Reads, Writes);
                  when CM.Stmt_Return | CM.Stmt_Delay =>
                     Collect_Shared_From_Expr (Item.Value, Reads, Writes);
                  when CM.Stmt_If =>
                     Collect_Shared_From_Expr (Item.Condition, Reads, Writes);
                     Collect_Shared_From_Statements (Item.Then_Stmts, Reads, Writes);
                     for Part of Item.Elsifs loop
                        Collect_Shared_From_Expr (Part.Condition, Reads, Writes);
                        Collect_Shared_From_Statements (Part.Statements, Reads, Writes);
                     end loop;
                     if Item.Has_Else then
                        Collect_Shared_From_Statements (Item.Else_Stmts, Reads, Writes);
                     end if;
                  when CM.Stmt_Case =>
                     Collect_Shared_From_Expr (Item.Case_Expr, Reads, Writes);
                     for Arm of Item.Case_Arms loop
                        Collect_Shared_From_Statements (Arm.Statements, Reads, Writes);
                     end loop;
                  when CM.Stmt_While =>
                     Collect_Shared_From_Expr (Item.Condition, Reads, Writes);
                     Collect_Shared_From_Statements (Item.Body_Stmts, Reads, Writes);
                  when CM.Stmt_For | CM.Stmt_Loop =>
                     Collect_Shared_From_Expr (Item.Loop_Range.Name_Expr, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Loop_Range.Low_Expr, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Loop_Range.High_Expr, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Loop_Iterable, Reads, Writes);
                     Collect_Shared_From_Statements (Item.Body_Stmts, Reads, Writes);
                  when CM.Stmt_Send =>
                     Collect_Shared_From_Expr (Item.Channel_Name, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Value, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Success_Var, Reads, Writes);
                  when CM.Stmt_Receive =>
                     Collect_Shared_From_Expr (Item.Channel_Name, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Target, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Success_Var, Reads, Writes);
                  when CM.Stmt_Try_Send =>
                     Raise_Internal ("unreachable: try_send rejected by resolver");
                  when CM.Stmt_Try_Receive =>
                     Collect_Shared_From_Expr (Item.Channel_Name, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Target, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Success_Var, Reads, Writes);
                  when CM.Stmt_Match =>
                     Collect_Shared_From_Expr (Item.Match_Expr, Reads, Writes);
                     for Arm of Item.Match_Arms loop
                        Collect_Shared_From_Statements (Arm.Statements, Reads, Writes);
                     end loop;
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Collect_Shared_From_Expr (Arm.Channel_Data.Channel_Name, Reads, Writes);
                              Collect_Shared_From_Statements (Arm.Channel_Data.Statements, Reads, Writes);
                           when CM.Select_Arm_Delay =>
                              Collect_Shared_From_Expr (Arm.Delay_Data.Duration_Expr, Reads, Writes);
                              Collect_Shared_From_Statements (Arm.Delay_Data.Statements, Reads, Writes);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Collect_Shared_From_Statements;

      Result : SU.Unbounded_String := SU.To_Unbounded_String ("");
      First  : Boolean := True;
   begin
      for Item of Summary.Reads loop
         declare
            Name : constant String := Normalize_Aspect_Name ("", FT.To_String (Item));
         begin
            if Starts_With (FT.To_String (Item), "param:")
              or else FT.To_String (Item) = "return"
              or else not Is_Aspect_State_Name (Name)
              or else Is_Constant_Object_Name (Unit, Name)
            then
               null;
            elsif Contains (Summary.Writes, FT.To_String (Item)) then
               Add_Unique (In_Outs, Name);
            elsif not Subprogram_Uses_Global_Name (Unit, Subprogram, Name) then
               null;
            else
               Add_Unique (Inputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Writes loop
         declare
            Name : constant String := Normalize_Aspect_Name ("", FT.To_String (Item));
         begin
            if Starts_With (FT.To_String (Item), "param:")
              or else FT.To_String (Item) = "return"
              or else not Is_Aspect_State_Name (Name)
              or else Is_Constant_Object_Name (Unit, Name)
            then
               null;
            elsif not Contains (Summary.Reads, FT.To_String (Item)) then
               Add_Unique (Outputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Channels loop
         declare
            Name : constant String := Normalize_Aspect_Name ("", FT.To_String (Item));
         begin
            if Is_Aspect_State_Name (Name) then
               Add_Unique (In_Outs, Name);
            end if;
         end;
      end loop;

      declare
         Shared_Reads  : FT.UString_Vectors.Vector;
         Shared_Writes : FT.UString_Vectors.Vector;
      begin
         for Decl of Subprogram.Declarations loop
            Collect_Shared_From_Expr (Decl.Initializer, Shared_Reads, Shared_Writes);
         end loop;
         Collect_Shared_From_Statements (Subprogram.Statements, Shared_Reads, Shared_Writes);
         for Name of Shared_Reads loop
            if Contains (Shared_Writes, FT.To_String (Name)) then
               Add_Unique (In_Outs, FT.To_String (Name));
            else
               Add_Unique (Inputs, FT.To_String (Name));
            end if;
         end loop;
         for Name of Shared_Writes loop
            if Contains (Shared_Reads, FT.To_String (Name)) then
               Add_Unique (In_Outs, FT.To_String (Name));
            else
               Add_Unique (Outputs, FT.To_String (Name));
            end if;
         end loop;
      end;

      if Inputs.Is_Empty and then Outputs.Is_Empty and then In_Outs.Is_Empty then
         return "null";
      end if;

      if not Inputs.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               ((if First then "" else ", ")
                & "Input => "
                & (if Inputs.Length = 1
                   then FT.To_String (Inputs (Inputs.First_Index))
                   else "(" & Join_Names (Inputs) & ")"));
         First := False;
      end if;

      if not Outputs.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               ((if First then "" else ", ")
                & "Output => "
                & (if Outputs.Length = 1
                   then FT.To_String (Outputs (Outputs.First_Index))
                   else "(" & Join_Names (Outputs) & ")"));
         First := False;
      end if;

      if not In_Outs.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               ((if First then "" else ", ")
                & "In_Out => "
                & (if In_Outs.Length = 1
                   then FT.To_String (In_Outs (In_Outs.First_Index))
                   else "(" & Join_Names (In_Outs) & ")"));
      end if;

      return "(" & SU.To_String (Result) & ")";
   end Render_Global_Aspect;
   function Render_Depends_Aspect
     (Unit       : CM.Resolved_Unit;
      Subprogram : CM.Resolved_Subprogram;
      Summary    : MB.Graph_Summary;
      Bronze     : MB.Bronze_Result) return String
   is
      pragma Unreferenced (Bronze);
      Result : SU.Unbounded_String;
      Allowed_Outputs : FT.UString_Vectors.Vector;
      Allowed_Inputs  : FT.UString_Vectors.Vector;
      Read_Param_Inputs : FT.UString_Vectors.Vector;

      function Contains
        (Items : FT.UString_Vectors.Vector;
         Name  : String) return Boolean is
      begin
         for Item of Items loop
            if FT.To_String (Item) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Contains;

      procedure Add_Unique
        (Items : in out FT.UString_Vectors.Vector;
         Name  : String) is
      begin
         if not Contains (Items, Name) then
            Items.Append (FT.To_UString (Name));
         end if;
      end Add_Unique;

      function Depends_Has_State_Output return Boolean is
      begin
         for Item of Summary.Depends loop
            if not Starts_With (FT.To_String (Item.Output_Name), "param:")
              and then FT.To_String (Item.Output_Name) /= "return"
            then
               return True;
            end if;
         end loop;
         return False;
      end Depends_Has_State_Output;

      function Map_Shared_State_Name (Name : String) return String is
      begin
         for Decl of Unit.Objects loop
            if Decl.Is_Shared and then not Decl.Names.Is_Empty then
               declare
                  Root_Name : constant String :=
                    FT.To_String (Decl.Names (Decl.Names.First_Index));
               begin
                  if Root_Name = Name then
                     return Shared_Wrapper_Object_Name (Root_Name);
                  end if;
               end;
            end if;
         end loop;
         return Name;
      end Map_Shared_State_Name;

      function Is_Shared_Wrapper_State_Name (Name : String) return Boolean is
      begin
         for Decl of Unit.Objects loop
            if Decl.Is_Shared and then not Decl.Names.Is_Empty then
               if Shared_Wrapper_Object_Name
                    (FT.To_String (Decl.Names (Decl.Names.First_Index))) = Name
               then
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end Is_Shared_Wrapper_State_Name;

   begin
      for Param of Subprogram.Params loop
         declare
            Name : constant String := FT.To_String (Param.Name);
            Mode : constant String := FT.To_String (Param.Mode);
         begin
            if Mode = "mut" then
               Add_Unique (Allowed_Outputs, Name);
               Add_Unique (Allowed_Inputs, Name);
            elsif Mode = "out" then
               Add_Unique (Allowed_Outputs, Name);
            elsif Mode = "in out" then
               Add_Unique (Allowed_Outputs, Name);
               Add_Unique (Allowed_Inputs, Name);
            else
               Add_Unique (Allowed_Inputs, Name);
            end if;
         end;
      end loop;

      if Subprogram.Has_Return_Type then
         Add_Unique
           (Allowed_Outputs,
            FT.To_String (Subprogram.Name) & "'Result");
      end if;

      for Item of Summary.Reads loop
         declare
            Name : constant String :=
              Map_Shared_State_Name
                (Normalize_Aspect_Name
                   (FT.To_String (Subprogram.Name), FT.To_String (Item)));
         begin
            if Starts_With (FT.To_String (Item), "param:")
              and then Is_Aspect_State_Name (Name)
            then
               Add_Unique (Read_Param_Inputs, Name);
            end if;
            if not Starts_With (FT.To_String (Item), "param:")
              and then FT.To_String (Item) /= "return"
              and then Is_Aspect_State_Name (Name)
              and then not Is_Constant_Object_Name (Unit, Name)
              and then Subprogram_Uses_Global_Name (Unit, Subprogram, Name)
            then
               Add_Unique (Allowed_Inputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Writes loop
         declare
            Name : constant String :=
              Map_Shared_State_Name
                (Normalize_Aspect_Name
                   (FT.To_String (Subprogram.Name), FT.To_String (Item)));
         begin
            if not Starts_With (FT.To_String (Item), "param:")
              and then FT.To_String (Item) /= "return"
              and then Is_Aspect_State_Name (Name)
              and then not Is_Constant_Object_Name (Unit, Name)
            then
               Add_Unique (Allowed_Outputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Channels loop
         declare
            Name : constant String :=
              Normalize_Aspect_Name (FT.To_String (Subprogram.Name), FT.To_String (Item));
         begin
            if Is_Aspect_State_Name (Name) then
               Add_Unique (Allowed_Inputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Depends loop
         declare
            Output_Name : constant String :=
              Map_Shared_State_Name
                (Normalize_Aspect_Name
                   (FT.To_String (Subprogram.Name), FT.To_String (Item.Output_Name)));
         begin
            if not Starts_With (FT.To_String (Item.Output_Name), "param:")
              and then FT.To_String (Item.Output_Name) /= "return"
              and then Is_Aspect_State_Name (Output_Name)
              and then not Is_Constant_Object_Name (Unit, Output_Name)
            then
               Add_Unique (Allowed_Outputs, Output_Name);
            end if;
            for Input of Item.Inputs loop
               declare
                  Name : constant String :=
                    Map_Shared_State_Name
                      (Normalize_Aspect_Name
                         (FT.To_String (Subprogram.Name), FT.To_String (Input)));
               begin
                  if not Starts_With (FT.To_String (Input), "param:")
                    and then FT.To_String (Input) /= "return"
                    and then Is_Aspect_State_Name (Name)
                    and then not Is_Constant_Object_Name (Unit, Name)
                    and then Subprogram_Uses_Global_Name (Unit, Subprogram, Name)
                  then
                     Add_Unique (Allowed_Inputs, Name);
                  end if;
               end;
            end loop;
         end;
      end loop;

      if not Summary.Channels.Is_Empty then
         return "";
      end if;

      if Summary.Depends.Is_Empty or else not Depends_Has_State_Output then
         return "";
      end if;

      for Index in Summary.Depends.First_Index .. Summary.Depends.Last_Index loop
         declare
            Item : constant MB.Depends_Entry := Summary.Depends (Index);
            Output_Name : constant String :=
              Map_Shared_State_Name
                (Normalize_Aspect_Name
                   (FT.To_String (Subprogram.Name), FT.To_String (Item.Output_Name)));
         begin
            if not Contains (Allowed_Outputs, Output_Name) then
               Raise_Internal
                 ("invalid Depends output `" & Output_Name
                  & "` while emitting `" & FT.To_String (Subprogram.Name) & "`");
            end if;
            if Index /= Summary.Depends.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result := Result & SU.To_Unbounded_String (Output_Name & " => ");
            declare
               Inputs : FT.UString_Vectors.Vector;
            begin
               for Input of Item.Inputs loop
                  declare
                     Input_Text : constant String := FT.To_String (Input);
                     Name : constant String :=
                       Map_Shared_State_Name
                         (Normalize_Aspect_Name
                            (FT.To_String (Subprogram.Name),
                             Input_Text));
                  begin
                     if Starts_With (Input_Text, "param:") then
                        if Contains (Allowed_Inputs, Name) then
                           Add_Unique (Inputs, Name);
                        end if;
                     elsif not Is_Aspect_State_Name (Name)
                       or else Is_Constant_Object_Name (Unit, Name)
                       or else not Subprogram_Uses_Global_Name (Unit, Subprogram, Name)
                     then
                        null;
                     elsif not Contains (Allowed_Inputs, Name) then
                        Raise_Internal
                          ("invalid Depends input `" & Name
                           & "` while emitting `" & FT.To_String (Subprogram.Name) & "`");
                     else
                        Add_Unique (Inputs, Name);
                     end if;
                  end;
               end loop;

               for Channel of Summary.Channels loop
                  declare
                     Name : constant String :=
                       Normalize_Aspect_Name
                         (FT.To_String (Subprogram.Name),
                          FT.To_String (Channel));
                  begin
                     if not Is_Aspect_State_Name (Name) then
                        null;
                     elsif not Contains (Allowed_Inputs, Name) then
                        Raise_Internal
                          ("invalid Depends input `" & Name
                           & "` while emitting `" & FT.To_String (Subprogram.Name) & "`");
                     else
                        Add_Unique (Inputs, Name);
                     end if;
                  end;
               end loop;

               for Input of Read_Param_Inputs loop
                  if Contains (Allowed_Inputs, FT.To_String (Input)) then
                     Add_Unique (Inputs, FT.To_String (Input));
                  end if;
               end loop;

               if Is_Shared_Wrapper_State_Name (Output_Name) then
                  Add_Unique (Inputs, Output_Name);
               end if;

               if Inputs.Is_Empty then
                  Result := Result & SU.To_Unbounded_String ("null");
               elsif Inputs.Length = 1 then
                  Result :=
                    Result
                    & SU.To_Unbounded_String (FT.To_String (Inputs (Inputs.First_Index)));
               else
                  Result :=
                    Result
                    & SU.To_Unbounded_String ("(" & Join_Names (Inputs) & ")");
               end if;
            end;
         end;
      end loop;

      return SU.To_String (Result);
   end Render_Depends_Aspect;
   function Render_Access_Param_Precondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String
   is
      Conditions : FT.UString_Vectors.Vector;
      Bound_Names : FT.UString_Vectors.Vector;

      function Is_Mutable_Param_Name (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name
              and then FT.To_String (Param.Mode) in "mut" | "in out"
            then
               return True;
            end if;
         end loop;
         return False;
      end Is_Mutable_Param_Name;

      function Needs_Non_Null_Param_Check (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name
              and then Is_Owner_Access (Param.Type_Info)
              and then not Param.Type_Info.Not_Null
            then
               return True;
            end if;
         end loop;
         return False;
      end Needs_Non_Null_Param_Check;

      function Is_Param_Name (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Is_Param_Name;

      function Expr_Allows_Null
        (Expr       : CM.Expr_Access;
         Param_Name : String) return Boolean
      is
         Operator : constant String :=
           (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));

         function Is_Direct_Param_Null_Equality return Boolean is
         begin
            return
              ((Expr.Left /= null
                and then Expr.Left.Kind = CM.Expr_Ident
                and then FT.To_String (Expr.Left.Name) = Param_Name
                and then Expr.Right /= null
                and then Expr.Right.Kind = CM.Expr_Null)
               or else
               (Expr.Right /= null
                and then Expr.Right.Kind = CM.Expr_Ident
                and then FT.To_String (Expr.Right.Name) = Param_Name
                and then Expr.Left /= null
                and then Expr.Left.Kind = CM.Expr_Null));
         end Is_Direct_Param_Null_Equality;
      begin
         if Expr = null then
            return False;
         elsif Expr.Kind = CM.Expr_Binary then
            if Operator = "=" then
               return Is_Direct_Param_Null_Equality;
            elsif Operator in "or" | "or else" then
               return
                 Expr_Allows_Null (Expr.Left, Param_Name)
                 or else Expr_Allows_Null (Expr.Right, Param_Name);
            end if;
         end if;
         return False;
      end Expr_Allows_Null;

      function Has_Leading_Null_Return_Guard (Param_Name : String) return Boolean is
      begin
         if Subprogram.Statements.Is_Empty then
            return False;
         end if;

         declare
            First_Stmt : constant CM.Statement_Access := Subprogram.Statements.First_Element;
         begin
            return
              First_Stmt /= null
              and then First_Stmt.Kind = CM.Stmt_If
              and then not First_Stmt.Then_Stmts.Is_Empty
              and then First_Stmt.Then_Stmts.First_Element /= null
              and then First_Stmt.Then_Stmts.First_Element.Kind = CM.Stmt_Return
              and then Expr_Allows_Null (First_Stmt.Condition, Param_Name);
         end;
      end Has_Leading_Null_Return_Guard;

      procedure Add_Unique (Condition : String) is
      begin
         if Condition'Length > 0 and then not Contains_Name (Conditions, Condition) then
            Conditions.Append (FT.To_UString (Condition));
         end if;
      end Add_Unique;

      procedure Add_Bound_Name (Name : String) is
      begin
         if Name'Length > 0 and then not Contains_Name (Bound_Names, Name) then
            Bound_Names.Append (FT.To_UString (Name));
         end if;
      end Add_Bound_Name;

      function Expr_Uses_Bound_Name (Expr : CM.Expr_Access) return Boolean is
      begin
         for Name of Bound_Names loop
            if Expr_Uses_Name (Expr, FT.To_String (Name)) then
               return True;
            end if;
         end loop;
         return False;
      end Expr_Uses_Bound_Name;

      procedure Add_Length_Precondition
        (Prefix     : CM.Expr_Access;
         Min_Length : Long_Long_Integer);

      procedure Collect_Expr (Expr : CM.Expr_Access);
      procedure Collect
        (Statements : CM.Statement_Access_Vectors.Vector);

      procedure Add_Length_Precondition
        (Prefix     : CM.Expr_Access;
         Min_Length : Long_Long_Integer)
      is
         Prefix_Root : constant String := Root_Name (Prefix);
         Prefix_Type : GM.Type_Descriptor := (others => <>);
      begin
         if Prefix = null or else Min_Length <= 0 then
            return;
         elsif Prefix_Root'Length = 0 or else not Is_Param_Name (Prefix_Root) then
            return;
         end if;

         Prefix_Type := Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Prefix));
         if Is_Growable_Array_Type (Unit, Document, Prefix_Type) then
            State.Needs_Safe_Array_RT := True;
            Add_Unique
              ("("
               & Array_Runtime_Instance_Name (Prefix_Type)
               & ".Length ("
               & Render_Expr (Unit, Document, Prefix, State)
               & ") >= "
               & Trim_Image (Min_Length)
               & ")");
         elsif Is_Bounded_String_Type (Prefix_Type) then
            Register_Bounded_String_Type (State, Prefix_Type);
            Add_Unique
              ("("
               & Bounded_String_Instance_Name (Prefix_Type)
               & ".Length ("
               & Render_Expr (Unit, Document, Prefix, State)
               & ") >= "
               & Trim_Image (Min_Length)
               & ")");
         elsif Is_Plain_String_Type (Unit, Document, Prefix_Type) then
            State.Needs_Safe_String_RT := True;
            Add_Unique
              ("(Safe_String_RT.Length ("
               & Render_Heap_String_Expr (Unit, Document, Prefix, State)
               & ") >= "
               & Trim_Image (Min_Length)
               & ")");
         end if;
      end Add_Length_Precondition;

      procedure Collect_Expr (Expr : CM.Expr_Access) is
         Index_Value : Long_Long_Integer := 0;
         High_Value  : Long_Long_Integer := 0;
      begin
         if Expr = null then
            return;
         end if;

         case Expr.Kind is
            when CM.Expr_Select | CM.Expr_Resolved_Index =>
               if Expr.Prefix /= null
                 and then Needs_Implicit_Dereference (Unit, Document, Expr.Prefix)
               then
                  declare
                     Param_Name : constant String := Root_Name (Expr.Prefix);
                  begin
                     if Param_Name'Length > 0
                       and then Needs_Non_Null_Param_Check (Param_Name)
                       and then not Has_Leading_Null_Return_Guard (Param_Name)
                     then
                        Add_Unique ("(" & Param_Name & " /= null)");
                     end if;
                  end;
               end if;
               if Expr.Kind = CM.Expr_Resolved_Index and then Expr.Prefix /= null then
                  if Natural (Expr.Args.Length) = 1
                    and then Try_Static_Integer_Value
                      (Expr.Args (Expr.Args.First_Index),
                       Index_Value)
                  then
                     Add_Length_Precondition (Expr.Prefix, Index_Value);
                  elsif Natural (Expr.Args.Length) = 2
                    and then Try_Static_Integer_Value
                      (Expr.Args (Expr.Args.First_Index + 1),
                       High_Value)
                  then
                     Add_Length_Precondition (Expr.Prefix, High_Value);
                  end if;
               end if;
            when others =>
               null;
         end case;

         Collect_Expr (Expr.Prefix);
         Collect_Expr (Expr.Callee);
         Collect_Expr (Expr.Inner);
         Collect_Expr (Expr.Left);
         Collect_Expr (Expr.Right);
         Collect_Expr (Expr.Value);
         Collect_Expr (Expr.Target);
         for Arg of Expr.Args loop
            Collect_Expr (Arg);
         end loop;
         for Field of Expr.Fields loop
            Collect_Expr (Field.Expr);
         end loop;
         for Element of Expr.Elements loop
            Collect_Expr (Element);
         end loop;
      end Collect_Expr;

      procedure Collect
        (Statements : CM.Statement_Access_Vectors.Vector) is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Assign =>
                     declare
                        Target_Name : constant String := Root_Name (Item.Target);
                        Target_Info : constant GM.Type_Descriptor :=
                          Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Item.Target));
                        Target_Type : constant String := Render_Type_Name (Target_Info);
                     begin
                        if Target_Name'Length > 0
                          and then Is_Mutable_Param_Name (Target_Name)
                          and then Is_Integer_Type (Unit, Document, Target_Info)
                          and then not Expr_Uses_Bound_Name (Item.Value)
                        then
                           declare
                              Wide_Image : constant String :=
                                Render_Wide_Expr (Unit, Document, Item.Value, State);
                           begin
                              Add_Unique
                                ("("
                                 & Wide_Image
                                 & " >= Safe_Runtime.Wide_Integer ("
                                 & Target_Type
                                 & "'First) and then "
                                 & Wide_Image
                                 & " <= Safe_Runtime.Wide_Integer ("
                                 & Target_Type
                                 & "'Last))");
                           end;
                        end if;
                        Collect_Expr (Item.Target);
                        Collect_Expr (Item.Value);
                     end;
                  when CM.Stmt_Call =>
                     Collect_Expr (Item.Call);
                  when CM.Stmt_Return =>
                     Collect_Expr (Item.Value);
                  when CM.Stmt_If =>
                     Collect_Expr (Item.Condition);
                     Collect (Item.Then_Stmts);
                     for Part of Item.Elsifs loop
                        Collect_Expr (Part.Condition);
                        Collect (Part.Statements);
                     end loop;
                     if Item.Has_Else then
                        Collect (Item.Else_Stmts);
                     end if;
                  when CM.Stmt_Case =>
                     Collect_Expr (Item.Case_Expr);
                     for Arm of Item.Case_Arms loop
                        Collect_Expr (Arm.Choice);
                        Collect (Arm.Statements);
                     end loop;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     declare
                        Bound_Count : constant Ada.Containers.Count_Type :=
                          Bound_Names.Length;
                     begin
                        Collect_Expr (Item.Condition);
                        Collect_Expr (Item.Loop_Range.Name_Expr);
                        Collect_Expr (Item.Loop_Range.Low_Expr);
                        Collect_Expr (Item.Loop_Range.High_Expr);
                        Collect_Expr (Item.Loop_Iterable);
                        if Item.Kind = CM.Stmt_For then
                           Add_Bound_Name (FT.To_String (Item.Loop_Var));
                        end if;
                        Collect (Item.Body_Stmts);
                        Bound_Names.Set_Length (Bound_Count);
                     end;
                  when CM.Stmt_Object_Decl =>
                     Collect_Expr (Item.Decl.Initializer);
                     for Name of Item.Decl.Names loop
                        Add_Bound_Name (FT.To_String (Name));
                     end loop;
                  when CM.Stmt_Destructure_Decl =>
                     Collect_Expr (Item.Destructure.Initializer);
                     for Name of Item.Destructure.Names loop
                        Add_Bound_Name (FT.To_String (Name));
                     end loop;
                  when CM.Stmt_Send | CM.Stmt_Receive | CM.Stmt_Try_Receive =>
                     Collect_Expr (Item.Channel_Name);
                     Collect_Expr (Item.Value);
                     Collect_Expr (Item.Target);
                     Collect_Expr (Item.Success_Var);
                  when CM.Stmt_Try_Send =>
                     Raise_Internal ("unreachable: try_send rejected by resolver");
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Collect_Expr (Arm.Channel_Data.Channel_Name);
                              Collect (Arm.Channel_Data.Statements);
                           when CM.Select_Arm_Delay =>
                              Collect_Expr (Arm.Delay_Data.Duration_Expr);
                              Collect (Arm.Delay_Data.Statements);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when CM.Stmt_Delay =>
                     Collect_Expr (Item.Value);
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Collect;

      Result : SU.Unbounded_String;
   begin
      for Param of Subprogram.Params loop
         if Is_Float_Type (Unit, Document, Param.Type_Info)
           and then Param.Type_Info.Has_Float_Low_Text
           and then Param.Type_Info.Has_Float_High_Text
         then
            Add_Unique
              ("("
               & FT.To_String (Param.Name)
               & " >= "
               & FT.To_String (Param.Type_Info.Float_Low_Text)
               & " and then "
               & FT.To_String (Param.Name)
               & " <= "
               & FT.To_String (Param.Type_Info.Float_High_Text)
               & ")");
         end if;
      end loop;
      for Decl of Subprogram.Declarations loop
         for Name of Decl.Names loop
            Add_Bound_Name (FT.To_String (Name));
         end loop;
      end loop;
      Collect (Subprogram.Statements);
      for Index in Conditions.First_Index .. Conditions.Last_Index loop
         if Index /= Conditions.First_Index then
            Result := Result & SU.To_Unbounded_String (" and then ");
         end if;
         Result := Result & SU.To_Unbounded_String (FT.To_String (Conditions (Index)));
      end loop;
      return SU.To_String (Result);
   end Render_Access_Param_Precondition;
   function Render_Access_Param_Postcondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String
   is
      Conditions   : FT.UString_Vectors.Vector;
      Seen_Targets : FT.UString_Vectors.Vector;
      Unsupported  : Boolean := False;

      function Is_Alias_Param_Name (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name
              and then Param.Type_Info.Anonymous
              and then Is_Alias_Access (Param.Type_Info)
              and then not Param.Type_Info.Is_Constant
            then
               return True;
            end if;
         end loop;
         return False;
      end Is_Alias_Param_Name;

      procedure Add_Unique_Equality
        (Target_Expr : CM.Expr_Access;
         Value_Expr  : CM.Expr_Access)
      is
         Target_Image : constant String := Render_Expr (Unit, Document, Target_Expr, State);
         Supported    : Boolean := True;
         Value_Image  : constant String :=
           Render_Expr_With_Old_Substitution
             (Unit, Document, Value_Expr, Target_Expr, State, Supported);
      begin
         if not Supported or else Target_Image'Length = 0 or else Value_Image'Length = 0 then
            Unsupported := True;
            return;
         end if;

         if Contains_Name (Seen_Targets, Target_Image) then
            Unsupported := True;
            return;
         end if;

         Seen_Targets.Append (FT.To_UString (Target_Image));
         Conditions.Append
           (FT.To_UString
              (Target_Image & " = " & Value_Image));
      end Add_Unique_Equality;

      procedure Add_Unique_Condition (Condition : String) is
      begin
         if Condition'Length > 0 and then not Contains_Name (Conditions, Condition) then
            Conditions.Append (FT.To_UString (Condition));
         end if;
      end Add_Unique_Condition;

      Result : SU.Unbounded_String;
   begin
      for Item of Subprogram.Statements loop
         exit when Unsupported;

         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Assign =>
                  declare
                     Target_Name : constant String := Root_Name (Item.Target);
                  begin
                     if Target_Name'Length > 0
                       and then Is_Alias_Param_Name (Target_Name)
                     then
                        Add_Unique_Equality (Item.Target, Item.Value);
                     end if;
                  end;
               when CM.Stmt_If
                  | CM.Stmt_Case
                  | CM.Stmt_While
                  | CM.Stmt_For
                  | CM.Stmt_Loop
                  | CM.Stmt_Select =>
                  Unsupported := True;
               when others =>
                  null;
            end case;
         end if;
      end loop;

      for Param of Subprogram.Params loop
         declare
            Mode : constant String := FT.To_String (Param.Mode);
            Name : constant String := FT.To_String (Param.Name);
         begin
            if Name'Length > 0
              and then Is_Owner_Access (Param.Type_Info)
              and then Mode in "mut" | "in out"
            then
               Add_Unique_Condition (Name & " /= null");
            end if;
         end;
      end loop;

      if Unsupported or else Conditions.Is_Empty then
         return "";
      end if;

      State.Needs_Unevaluated_Use_Of_Old := True;
      for Index in Conditions.First_Index .. Conditions.Last_Index loop
         if Index /= Conditions.First_Index then
            Result := Result & SU.To_Unbounded_String (" and then ");
         end if;
         Result := Result & SU.To_Unbounded_String (FT.To_String (Conditions (Index)));
      end loop;
      return SU.To_String (Result);
   end Render_Access_Param_Postcondition;
   function Uses_Structural_Traversal_Lowering
     (Subprogram : CM.Resolved_Subprogram) return Boolean
   is
      Subprogram_Name : constant String :=
        FT.Lowercase (FT.To_String (Subprogram.Name));

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean;

      function Is_Single_Return_Block
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;

      function Is_Recursive_Tail_Return
        (Statements : CM.Statement_Access_Vectors.Vector;
         Expected_Param_Name : String) return Boolean;

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean
      is
         Operator : constant String :=
           (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
      begin
         return
           Expr /= null
           and then Expr.Kind = CM.Expr_Binary
           and then Operator = "="
           and then
             ((Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Left.Name) = Name
               and then Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Null)
              or else
              (Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Right.Name) = Name
               and then Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Null));
      end Is_Direct_Null_Check;

      function Is_Single_Return_Block
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
      is
      begin
         return
           Statements.Length = 1
           and then Statements (Statements.First_Index) /= null
           and then Statements (Statements.First_Index).Kind = CM.Stmt_Return
           and then Statements (Statements.First_Index).Value /= null;
      end Is_Single_Return_Block;

      function Is_Recursive_Tail_Return
        (Statements : CM.Statement_Access_Vectors.Vector;
         Expected_Param_Name : String) return Boolean
      is
         Return_Stmt : CM.Statement_Access := null;
         Call_Expr   : CM.Expr_Access := null;
      begin
         if Statements.Length /= 1 then
            return False;
         end if;

         Return_Stmt := Statements (Statements.First_Index);
         if Return_Stmt = null
           or else Return_Stmt.Kind /= CM.Stmt_Return
           or else Return_Stmt.Value = null
           or else Return_Stmt.Value.Kind /= CM.Expr_Call
         then
            return False;
         end if;

         Call_Expr := Return_Stmt.Value;
         return
           Call_Expr.Callee /= null
           and then FT.Lowercase (CM.Flatten_Name (Call_Expr.Callee)) = Subprogram_Name
           and then Call_Expr.Args.Length = Subprogram.Params.Length
           and then not Call_Expr.Args.Is_Empty
           and then Root_Name (Call_Expr.Args (Call_Expr.Args.First_Index)) = Expected_Param_Name;
      end Is_Recursive_Tail_Return;
   begin
      if Subprogram.Params.Is_Empty or else Subprogram.Statements.Is_Empty then
         return False;
      end if;

      declare
         First_Param_Name : constant String :=
           FT.To_String (Subprogram.Params (Subprogram.Params.First_Index).Name);
      begin
         if First_Param_Name'Length = 0
           or else not Is_Owner_Access
             (Subprogram.Params (Subprogram.Params.First_Index).Type_Info)
         then
            return False;
         end if;

         if Subprogram.Declarations.Is_Empty
           and then Subprogram.Params.Length = 1
           and then Subprogram.Statements.Length = 1
           and then Subprogram.Statements (Subprogram.Statements.First_Index) /= null
           and then Subprogram.Statements (Subprogram.Statements.First_Index).Kind = CM.Stmt_If
         then
            declare
               If_Stmt : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.First_Index);
            begin
               if Is_Direct_Null_Check (If_Stmt.Condition, First_Param_Name)
                 and then Is_Single_Return_Block (If_Stmt.Then_Stmts)
                 and then If_Stmt.Has_Else
                 and then Is_Recursive_Tail_Return (If_Stmt.Else_Stmts, First_Param_Name)
               then
                  for Part of If_Stmt.Elsifs loop
                     if not Is_Single_Return_Block (Part.Statements) then
                        return False;
                     end if;
                  end loop;
                  return True;
               end if;
            end;
         end if;

         if not Subprogram.Declarations.Is_Empty
           and then Subprogram.Params.Length >= 2
           and then Subprogram.Statements.Length >= 4
         then
            declare
               First_Stmt       : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.First_Index);
               Recursive_Assign : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.Last_Index - 1);
               Final_Return     : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.Last_Index);
            begin
               if First_Stmt /= null
                 and then First_Stmt.Kind = CM.Stmt_If
                 and then Is_Single_Return_Block (First_Stmt.Then_Stmts)
                 and then not First_Stmt.Has_Else
                 and then First_Stmt.Elsifs.Is_Empty
                 and then Recursive_Assign /= null
                 and then Recursive_Assign.Kind = CM.Stmt_Assign
                 and then Recursive_Assign.Value /= null
                 and then Recursive_Assign.Value.Kind = CM.Expr_Call
                 and then Recursive_Assign.Value.Callee /= null
                 and then FT.Lowercase (CM.Flatten_Name (Recursive_Assign.Value.Callee)) = Subprogram_Name
                 and then Recursive_Assign.Value.Args.Length = Subprogram.Params.Length
                 and then Root_Name (Recursive_Assign.Value.Args (Recursive_Assign.Value.Args.First_Index)) = First_Param_Name
                 and then Final_Return /= null
                 and then Final_Return.Kind = CM.Stmt_Return
                 and then Root_Name (Final_Return.Value) = Root_Name (Recursive_Assign.Target)
               then
                  return True;
               end if;
            end;
         end if;
      end;

      return False;
   end Uses_Structural_Traversal_Lowering;
   function Structural_Accumulator_Count_Total_Bound
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Count_Name : String;
      Total_Name : String;
      State      : in out Emit_State) return String
   is
      Count_Param  : constant CM.Symbol :=
        Subprogram.Params (Subprogram.Params.First_Index + 1);
      Total_Param  : constant CM.Symbol :=
        Subprogram.Params (Subprogram.Params.First_Index + 2);
      Count_Base   : constant GM.Type_Descriptor :=
        Base_Type (Unit, Document, Count_Param.Type_Info);
      Total_Base   : constant GM.Type_Descriptor :=
        Base_Type (Unit, Document, Total_Param.Type_Info);
      Count_High   : CM.Wide_Integer;
      Total_High   : CM.Wide_Integer;
      Step_Limit   : CM.Wide_Integer;
   begin
      if Subprogram.Params.Length < 3
        or else not Is_Integer_Type (Unit, Document, Count_Param.Type_Info)
        or else not Is_Integer_Type (Unit, Document, Total_Param.Type_Info)
        or else not Count_Base.Has_Low
        or else not Count_Base.Has_High
        or else not Total_Base.Has_Low
        or else not Total_Base.Has_High
        or else Count_Base.Low /= 0
        or else Total_Base.Low /= 0
        or else Count_Base.High <= 0
      then
         return "";
      end if;

      Count_High := CM.Wide_Integer (Count_Base.High);
      Total_High := CM.Wide_Integer (Total_Base.High);
      if Total_High < 0 or else Total_High mod Count_High /= 0 then
         return "";
      end if;

      Step_Limit := Total_High / Count_High;
      State.Needs_Safe_Runtime := True;
      return
        "Safe_Runtime.Wide_Integer ("
        & Total_Name
        & ") <= Safe_Runtime.Wide_Integer ("
        & Count_Name
        & ") * "
        & Trim_Wide_Image (Step_Limit);
   end Structural_Accumulator_Count_Total_Bound;

   function Render_Inferred_Result_Postcondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String
   is
      --  Emit only branch-equality facts. A range claim for clamp(value, lo, hi)
      --  would be unsound when callers pass lo > hi.
      Function_Name : constant String := FT.To_String (Subprogram.Name);

      function Is_Integer_Non_Boolean_Type (Info : GM.Type_Descriptor) return Boolean;
      function Is_Read_Only_Integer_Param (Param : CM.Symbol) return Boolean;
      function Is_Param_Name (Name : String) return Boolean;
      function Is_Safe_Condition (Expr : CM.Expr_Access) return Boolean;
      function Is_Safe_Return (Expr : CM.Expr_Access) return Boolean;
      function Render_Post_Expr (Expr : CM.Expr_Access) return String;
      function Safe_Condition_Image (Expr : CM.Expr_Access) return String;
      function Safe_Return_Image (Expr : CM.Expr_Access) return String;
      function Return_Statement_Image (Stmt : CM.Statement_Access) return String;
      function Single_Return_Image
        (Statements : CM.Statement_Access_Vectors.Vector) return String;
      function Result_Equality (Expr_Image : String) return String;

      function Is_Integer_Non_Boolean_Type (Info : GM.Type_Descriptor) return Boolean is
         Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
         Name : constant String := FT.Lowercase (FT.To_String (Base.Name));
      begin
         return
           Is_Integer_Type (Unit, Document, Info)
           and then Kind /= "boolean"
           and then Name /= "boolean";
      end Is_Integer_Non_Boolean_Type;

      function Is_Read_Only_Integer_Param (Param : CM.Symbol) return Boolean is
         Mode : constant String := FT.Lowercase (FT.To_String (Param.Mode));
      begin
         return
           Mode not in "mut" | "in out" | "out"
           and then Is_Integer_Non_Boolean_Type (Param.Type_Info);
      end Is_Read_Only_Integer_Param;

      function Is_Param_Name (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Is_Param_Name;

      function Is_Safe_Condition (Expr : CM.Expr_Access) return Boolean is
         Operator : constant String :=
           (if Expr = null then "" else FT.To_String (Expr.Operator));
      begin
         if Expr = null then
            return False;
         end if;

         case Expr.Kind is
            when CM.Expr_Int =>
               return True;
            when CM.Expr_Ident =>
               if Is_Param_Name (FT.To_String (Expr.Name)) then
                  return True;
               end if;
            when CM.Expr_Unary =>
               if Operator in "+" | "-" then
                  return Is_Safe_Condition (Expr.Inner);
               end if;
            when CM.Expr_Binary =>
               --  Safe equality reaches MIR as == / !=; Render_Expr maps those to Ada = / /=.
               if Operator in "<" | "<=" | ">" | ">=" | "=" | "==" | "/=" | "!="
                 | "and then" | "or else" | "+" | "-"
               then
                  return Is_Safe_Condition (Expr.Left)
                    and then Is_Safe_Condition (Expr.Right);
               end if;
            when others =>
               null;
         end case;

         return False;
      end Is_Safe_Condition;

      function Is_Safe_Return (Expr : CM.Expr_Access) return Boolean is
         Operator : constant String :=
           (if Expr = null then "" else FT.To_String (Expr.Operator));
      begin
         if Expr = null then
            return False;
         end if;

         case Expr.Kind is
            when CM.Expr_Int =>
               return True;
            when CM.Expr_Ident =>
               if Is_Param_Name (FT.To_String (Expr.Name)) then
                  return True;
               end if;
            when CM.Expr_Unary =>
               if Operator in "+" | "-" then
                  return Is_Safe_Return (Expr.Inner);
               end if;
            when CM.Expr_Binary =>
               if Operator in "+" | "-" then
                  return Is_Safe_Return (Expr.Left)
                    and then Is_Safe_Return (Expr.Right);
               end if;
            when others =>
               null;
         end case;

         return False;
      end Is_Safe_Return;

      function Render_Post_Expr (Expr : CM.Expr_Access) return String is
         Local_State : Emit_State := State;
      begin
         return Render_Expr (Unit, Document, Expr, Local_State);
      end Render_Post_Expr;

      function Safe_Condition_Image (Expr : CM.Expr_Access) return String is
      begin
         if Is_Safe_Condition (Expr) then
            return Render_Post_Expr (Expr);
         end if;

         return "";
      end Safe_Condition_Image;

      function Safe_Return_Image (Expr : CM.Expr_Access) return String is
      begin
         if Is_Safe_Return (Expr) then
            return Render_Post_Expr (Expr);
         end if;

         return "";
      end Safe_Return_Image;

      function Return_Statement_Image (Stmt : CM.Statement_Access) return String is
      begin
         if Stmt = null
           or else Stmt.Kind /= CM.Stmt_Return
           or else Stmt.Value = null
         then
            return "";
         end if;

         return Safe_Return_Image (Stmt.Value);
      end Return_Statement_Image;

      function Single_Return_Image
        (Statements : CM.Statement_Access_Vectors.Vector) return String is
      begin
         if Statements.Length /= 1 then
            return "";
         end if;

         return Return_Statement_Image (Statements (Statements.First_Index));
      end Single_Return_Image;

      function Result_Equality (Expr_Image : String) return String is
      begin
         if Expr_Image'Length = 0 then
            return "";
         end if;

         return Function_Name & "'Result = " & Expr_Image;
      end Result_Equality;

      If_Stmt    : CM.Statement_Access := null;
      Else_Image : SU.Unbounded_String;
      Result     : SU.Unbounded_String;
   begin
      if Function_Name'Length = 0
        or else not Subprogram.Has_Return_Type
        or else Subprogram.Params.Is_Empty
        or else not Subprogram.Declarations.Is_Empty
        or else not Is_Integer_Non_Boolean_Type (Subprogram.Return_Type)
        or else
          (Subprogram.Statements.Length /= 1 and then Subprogram.Statements.Length /= 2)
      then
         return "";
      end if;

      for Param of Subprogram.Params loop
         if not Is_Read_Only_Integer_Param (Param) then
            return "";
         end if;
      end loop;

      If_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
      if If_Stmt = null
        or else If_Stmt.Kind /= CM.Stmt_If
        or else If_Stmt.Elsifs.Is_Empty
      then
         return "";
      end if;

      if Subprogram.Statements.Length = 1 then
         if not If_Stmt.Has_Else then
            return "";
         end if;
         Else_Image :=
           SU.To_Unbounded_String
             (Result_Equality (Single_Return_Image (If_Stmt.Else_Stmts)));
      else
         if If_Stmt.Has_Else then
            return "";
         end if;
         Else_Image :=
           SU.To_Unbounded_String
             (Result_Equality
                (Return_Statement_Image
                   (Subprogram.Statements (Subprogram.Statements.Last_Index))));
      end if;

      if SU.Length (Else_Image) = 0 then
         return "";
      end if;

      declare
         Condition_Image : constant String := Safe_Condition_Image (If_Stmt.Condition);
         Then_Image      : constant String :=
           Result_Equality (Single_Return_Image (If_Stmt.Then_Stmts));
      begin
         if Condition_Image'Length = 0 or else Then_Image'Length = 0 then
            return "";
         end if;

         Result :=
           SU.To_Unbounded_String
             ("(if "
              & Condition_Image
              & " then "
              & Then_Image);
      end;

      for Part of If_Stmt.Elsifs loop
         declare
            Condition_Image : constant String := Safe_Condition_Image (Part.Condition);
            Branch_Image    : constant String :=
              Result_Equality (Single_Return_Image (Part.Statements));
         begin
            if Condition_Image'Length = 0 or else Branch_Image'Length = 0 then
               return "";
            end if;

            Result :=
              Result
              & SU.To_Unbounded_String
                  (" elsif "
                   & Condition_Image
                   & " then "
                   & Branch_Image);
         end;
      end loop;

      Result := Result & SU.To_Unbounded_String (" else " & SU.To_String (Else_Image) & ")");
      return SU.To_String (Result);
   end Render_Inferred_Result_Postcondition;

   function Effective_Subprogram_Outer_Declarations
     (Subprogram              : CM.Resolved_Subprogram;
      Raw_Outer_Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector
   is
      function Later_Outer_Declarations_Use_Name
        (Decl_Index : Positive;
         Name       : String) return Boolean is
      begin
         if Raw_Outer_Declarations.Is_Empty
           or else Decl_Index >= Raw_Outer_Declarations.Last_Index
         then
            return False;
         end if;

         for Later_Index in Decl_Index + 1 .. Raw_Outer_Declarations.Last_Index loop
            declare
               Later_Decl : constant CM.Resolved_Object_Decl :=
                 Raw_Outer_Declarations (Later_Index);
            begin
               if Later_Decl.Initializer /= null
                 and then Expr_Uses_Name (Later_Decl.Initializer, Name)
               then
                  return True;
               end if;
            end;
         end loop;

         return False;
      end Later_Outer_Declarations_Use_Name;

      function Should_Elide_Dead_Owner_Decl
        (Decl_Index : Positive;
         Decl       : CM.Resolved_Object_Decl) return Boolean is
         Decl_Name : constant String :=
           FT.To_String (Decl.Names (Decl.Names.First_Index));
      begin
         return
           not Decl.Is_Constant
           and then Is_Owner_Access (Decl.Type_Info)
           and then Decl.Has_Initializer
           and then Decl.Names.Length = 1
           and then Decl.Initializer /= null
           and then Decl.Initializer.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
           and then not
             Statements_Use_Name (Subprogram.Statements, Decl_Name)
           and then not Later_Outer_Declarations_Use_Name (Decl_Index, Decl_Name);
      end Should_Elide_Dead_Owner_Decl;

      Result : CM.Resolved_Object_Decl_Vectors.Vector;
   begin
      for Decl_Index in Raw_Outer_Declarations.First_Index .. Raw_Outer_Declarations.Last_Index loop
         declare
            Decl : constant CM.Resolved_Object_Decl :=
              Raw_Outer_Declarations (Decl_Index);
         begin
            if not Should_Elide_Dead_Owner_Decl (Decl_Index, Decl) then
               Result.Append (Decl);
            end if;
         end;
      end loop;
      return Result;
   end Effective_Subprogram_Outer_Declarations;
   function Render_Structural_Traversal_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return Boolean
   is
      Subprogram_Name : constant String :=
        FT.Lowercase (FT.To_String (Subprogram.Name));

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean;

      function Single_Return_Expr
        (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access;

      function Recursive_Call_From_Return
        (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access;

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean
      is
         Operator : constant String :=
           (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
      begin
         return
           Expr /= null
           and then Expr.Kind = CM.Expr_Binary
           and then Operator = "="
           and then
             ((Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Left.Name) = Name
               and then Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Null)
              or else
              (Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Right.Name) = Name
               and then Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Null));
      end Is_Direct_Null_Check;

      function Single_Return_Expr
        (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access
      is
      begin
         if Statements.Length /= 1
           or else Statements (Statements.First_Index) = null
           or else Statements (Statements.First_Index).Kind /= CM.Stmt_Return
         then
            return null;
         end if;

         return Statements (Statements.First_Index).Value;
      end Single_Return_Expr;

      function Recursive_Call_From_Return
        (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access
      is
         Return_Expr : constant CM.Expr_Access := Single_Return_Expr (Statements);
      begin
         if Return_Expr /= null
           and then Return_Expr.Kind = CM.Expr_Call
           and then Return_Expr.Callee /= null
           and then FT.Lowercase (CM.Flatten_Name (Return_Expr.Callee)) = Subprogram_Name
         then
            return Return_Expr;
         end if;
         return null;
      end Recursive_Call_From_Return;

      function Render_Structural_Observer return Boolean is
         Param               : constant CM.Symbol :=
           Subprogram.Params (Subprogram.Params.First_Index);
         Param_Name          : constant String := FT.To_String (Param.Name);
         Param_Image         : constant String := Ada_Safe_Name (Param_Name);
         Cursor_Name         : constant String := "Cursor";
         Cursor_Type_Image   : constant String :=
           (if Has_Text (Param.Type_Info.Target)
            then "access constant " & FT.To_String (Param.Type_Info.Target)
            else "");
         If_Stmt             : CM.Statement_Access := null;
         Recursive_Call      : CM.Expr_Access := null;
         Default_Return_Expr : CM.Expr_Access := null;
         From_Names          : FT.UString_Vectors.Vector;
         To_Names            : FT.UString_Vectors.Vector;
      begin
         if not Subprogram.Declarations.Is_Empty
           or else Subprogram.Params.Length /= 1
           or else Subprogram.Statements.Length /= 1
           or else not Is_Owner_Access (Param.Type_Info)
           or else Cursor_Type_Image'Length = 0
         then
            return False;
         end if;

         If_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
         if If_Stmt = null
           or else If_Stmt.Kind /= CM.Stmt_If
           or else not Is_Direct_Null_Check (If_Stmt.Condition, Param_Name)
           or else not If_Stmt.Has_Else
         then
            return False;
         end if;

         Default_Return_Expr := Single_Return_Expr (If_Stmt.Then_Stmts);
         Recursive_Call := Recursive_Call_From_Return (If_Stmt.Else_Stmts);
         if Default_Return_Expr = null
           or else Recursive_Call = null
           or else Recursive_Call.Args.Length /= 1
           or else Root_Name (Recursive_Call.Args (Recursive_Call.Args.First_Index)) /= Param_Name
         then
            return False;
         end if;

         for Part of If_Stmt.Elsifs loop
            if Single_Return_Expr (Part.Statements) = null then
               return False;
            end if;
         end loop;

         From_Names.Append (FT.To_UString (Param_Image));
         To_Names.Append (FT.To_UString (Cursor_Name));

         Append_Line
           (Buffer,
            Cursor_Name & " : " & Cursor_Type_Image & " := " & Param_Image & ";",
            2);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "while " & Cursor_Name & " /= null loop", 2);
         Append_Line (Buffer, "pragma Loop_Variant (Structural => " & Cursor_Name & ");", 3);

         for Part of If_Stmt.Elsifs loop
            declare
               Branch_Return : constant CM.Expr_Access := Single_Return_Expr (Part.Statements);
            begin
               Append_Line
                 (Buffer,
                  "if "
                  & Apply_Name_Replacements
                      (Render_Expr (Unit, Document, Part.Condition, State),
                       From_Names,
                       To_Names)
                  & " then",
                  3);
               Append_Line
                 (Buffer,
                  "return "
                  & Apply_Name_Replacements
                      (Render_Expr (Unit, Document, Branch_Return, State),
                       From_Names,
                       To_Names)
                  & ";",
                  4);
               Append_Line (Buffer, "end if;", 3);
            end;
         end loop;

         Append_Line
           (Buffer,
            Cursor_Name
            & " := "
            & Apply_Name_Replacements
                (Render_Expr
                   (Unit,
                    Document,
                    Recursive_Call.Args (Recursive_Call.Args.First_Index),
                    State),
                 From_Names,
                 To_Names)
            & ";",
            3);
         Append_Line (Buffer, "end loop;", 2);
         Append_Line
           (Buffer,
            "return "
            & Apply_Name_Replacements
                (Render_Expr (Unit, Document, Default_Return_Expr, State),
                 From_Names,
                 To_Names)
            & ";",
            2);
         return True;
      end Render_Structural_Observer;

      function Render_Structural_Accumulator return Boolean is
         First_Param        : constant CM.Symbol :=
           Subprogram.Params (Subprogram.Params.First_Index);
         First_Param_Name   : constant String := FT.To_String (First_Param.Name);
         First_Param_Image  : constant String := Ada_Safe_Name (First_Param_Name);
         Cursor_Name        : constant String := "Cursor";
         Cursor_Type_Image  : constant String :=
           (if Has_Text (First_Param.Type_Info.Target)
            then "access constant " & FT.To_String (First_Param.Type_Info.Target)
            else "");
         First_Stmt         : CM.Statement_Access := null;
         Recursive_Assign   : CM.Statement_Access := null;
         Final_Return       : CM.Statement_Access := null;
         Recursive_Call     : CM.Expr_Access := null;
         Entry_Exit_Image   : SU.Unbounded_String := SU.Null_Unbounded_String;
         Final_Return_Image : SU.Unbounded_String := SU.Null_Unbounded_String;
         Bound_Image        : SU.Unbounded_String := SU.Null_Unbounded_String;
         From_Names         : FT.UString_Vectors.Vector;
         To_Names           : FT.UString_Vectors.Vector;
         State_Names        : FT.UString_Vectors.Vector;
      begin
         if Subprogram.Declarations.Is_Empty
           or else Subprogram.Params.Length < 2
           or else Subprogram.Statements.Length < 4
           or else not Is_Owner_Access (First_Param.Type_Info)
           or else Cursor_Type_Image'Length = 0
         then
            return False;
         end if;

         First_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
         Recursive_Assign := Subprogram.Statements (Subprogram.Statements.Last_Index - 1);
         Final_Return := Subprogram.Statements (Subprogram.Statements.Last_Index);
         if First_Stmt = null
           or else First_Stmt.Kind /= CM.Stmt_If
           or else Single_Return_Expr (First_Stmt.Then_Stmts) = null
           or else First_Stmt.Has_Else
           or else not First_Stmt.Elsifs.Is_Empty
           or else Recursive_Assign = null
           or else Recursive_Assign.Kind /= CM.Stmt_Assign
           or else Recursive_Assign.Value = null
           or else Recursive_Assign.Value.Kind /= CM.Expr_Call
           or else Recursive_Assign.Value.Callee = null
           or else FT.Lowercase (CM.Flatten_Name (Recursive_Assign.Value.Callee)) /= Subprogram_Name
           or else Final_Return = null
           or else Final_Return.Kind /= CM.Stmt_Return
           or else Root_Name (Final_Return.Value) /= Root_Name (Recursive_Assign.Target)
         then
            return False;
         end if;

         Recursive_Call := Recursive_Assign.Value;
         if Recursive_Call.Args.Length /= Subprogram.Params.Length
           or else Root_Name (Recursive_Call.Args (Recursive_Call.Args.First_Index)) /= First_Param_Name
         then
            return False;
         end if;

         From_Names.Append (FT.To_UString (First_Param_Image));
         To_Names.Append (FT.To_UString (Cursor_Name));

         for Param_Index in Subprogram.Params.First_Index + 1 .. Subprogram.Params.Last_Index loop
            declare
               Param      : constant CM.Symbol := Subprogram.Params (Param_Index);
               Param_Name : constant String := Ada_Safe_Name (FT.To_String (Param.Name));
               State_Name : constant String := Param_Name & "_State";
            begin
               State_Names.Append (FT.To_UString (State_Name));
               From_Names.Append (FT.To_UString (Param_Name));
               To_Names.Append (FT.To_UString (State_Name));
            end;
         end loop;

         for Arg_Index in Recursive_Call.Args.First_Index + 1 .. Recursive_Call.Args.Last_Index loop
            declare
               Root : constant String := Ada_Safe_Name (Root_Name (Recursive_Call.Args (Arg_Index)));
            begin
               if Root'Length > 0 then
                  From_Names.Append (FT.To_UString (Root));
                  To_Names.Append
                    (State_Names
                       (State_Names.First_Index
                        + (Arg_Index - (Recursive_Call.Args.First_Index + 1))));
               end if;
            end;
         end loop;

         declare
            Leading_Condition : constant CM.Expr_Access := First_Stmt.Condition;
            Operator          : constant String :=
              (if Leading_Condition = null then "" else Map_Operator (FT.To_String (Leading_Condition.Operator)));
            Leading_Return    : constant CM.Expr_Access :=
              Single_Return_Expr (First_Stmt.Then_Stmts);
         begin
            if Is_Direct_Null_Check (Leading_Condition, First_Param_Name) then
               null;
            elsif Leading_Condition /= null
              and then Leading_Condition.Kind = CM.Expr_Binary
              and then Operator = "or else"
            then
               if Is_Direct_Null_Check (Leading_Condition.Left, First_Param_Name) then
                  Entry_Exit_Image :=
                    SU.To_Unbounded_String
                      (Apply_Name_Replacements
                         (Render_Expr (Unit, Document, Leading_Condition.Right, State),
                          From_Names,
                          To_Names));
               elsif Is_Direct_Null_Check (Leading_Condition.Right, First_Param_Name) then
                  Entry_Exit_Image :=
                    SU.To_Unbounded_String
                      (Apply_Name_Replacements
                         (Render_Expr (Unit, Document, Leading_Condition.Left, State),
                          From_Names,
                          To_Names));
               else
                  return False;
               end if;
            else
               return False;
            end if;

            Final_Return_Image :=
              SU.To_Unbounded_String
                (Apply_Name_Replacements
                   (Render_Expr (Unit, Document, Leading_Return, State),
                    From_Names,
                    To_Names));
         end;

         Append_Line
           (Buffer,
            Cursor_Name & " : " & Cursor_Type_Image & " := " & First_Param_Image & ";",
            2);
         for Param_Index in Subprogram.Params.First_Index + 1 .. Subprogram.Params.Last_Index loop
            declare
               Param      : constant CM.Symbol := Subprogram.Params (Param_Index);
               State_Name : constant String :=
                 FT.To_String
                   (State_Names
                      (State_Names.First_Index
                       + (Param_Index - (Subprogram.Params.First_Index + 1))));
            begin
               Append_Line
                 (Buffer,
                  State_Name
                  & " : "
                  & Render_Type_Name (Param.Type_Info)
                  & " := "
                  & Ada_Safe_Name (FT.To_String (Param.Name))
                  & ";",
                  2);
            end;
         end loop;

         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "while " & Cursor_Name & " /= null loop", 2);
         Append_Line (Buffer, "pragma Loop_Variant (Structural => " & Cursor_Name & ");", 3);
         for Param_Index in Subprogram.Params.First_Index + 1 .. Subprogram.Params.Last_Index loop
            declare
               Param      : constant CM.Symbol := Subprogram.Params (Param_Index);
               State_Name : constant String :=
                 FT.To_String
                   (State_Names
                      (State_Names.First_Index
                       + (Param_Index - (Subprogram.Params.First_Index + 1))));
            begin
               if not Is_Access_Type (Param.Type_Info) then
                  Append_Line
                    (Buffer,
                     "pragma Loop_Invariant ("
                     & State_Name
                     & " in "
                     & Render_Type_Name (Param.Type_Info)
                     & ");",
                     3);
               end if;
            end;
         end loop;
         if State_Names.Length >= 2 then
            Bound_Image :=
              SU.To_Unbounded_String
                (Structural_Accumulator_Count_Total_Bound
                   (Unit,
                    Document,
                    Subprogram,
                    FT.To_String (State_Names (State_Names.First_Index)),
                    FT.To_String (State_Names (State_Names.First_Index + 1)),
                    State));
            if SU.Length (Bound_Image) > 0 then
               Append_Line
                 (Buffer,
                  "pragma Loop_Invariant (" & SU.To_String (Bound_Image) & ");",
                  3);
            end if;
         end if;

         if SU.Length (Entry_Exit_Image) > 0 then
            Append_Line (Buffer, "exit when " & SU.To_String (Entry_Exit_Image) & ";", 3);
         end if;

         for Statement_Index in Subprogram.Statements.First_Index + 1 .. Subprogram.Statements.Last_Index - 2 loop
            declare
               Item : constant CM.Statement_Access := Subprogram.Statements (Statement_Index);
            begin
               if Item = null then
                  return False;
               end if;

               case Item.Kind is
                  when CM.Stmt_Assign =>
                     declare
                        Target_Name : constant String :=
                          Apply_Name_Replacements
                            (Ada_Safe_Name (Root_Name (Item.Target)),
                             From_Names,
                             To_Names);
                     begin
                        if Target_Name'Length = 0 then
                           return False;
                        end if;

                        Append_Line
                          (Buffer,
                           Target_Name
                           & " := "
                           & Apply_Name_Replacements
                               (Render_Expr (Unit, Document, Item.Value, State),
                                From_Names,
                                To_Names)
                           & ";",
                           3);
                     end;
                  when CM.Stmt_If =>
                     declare
                        Branch_Return : constant CM.Expr_Access :=
                          Single_Return_Expr (Item.Then_Stmts);
                        Branch_Return_Image : constant String :=
                          (if Branch_Return = null
                           then ""
                           else
                             Apply_Name_Replacements
                               (Render_Expr
                                  (Unit,
                                   Document,
                                   Branch_Return,
                                   State),
                                From_Names,
                                To_Names));
                     begin
                        if Branch_Return = null
                          or else Item.Has_Else
                          or else not Item.Elsifs.Is_Empty
                          or else Branch_Return_Image /= SU.To_String (Final_Return_Image)
                        then
                           return False;
                        end if;

                        Append_Line
                          (Buffer,
                           "exit when "
                           & Apply_Name_Replacements
                               (Render_Expr (Unit, Document, Item.Condition, State),
                                From_Names,
                                To_Names)
                           & ";",
                           3);
                     end;
                  when others =>
                     return False;
               end case;
            end;
         end loop;

         Append_Line
           (Buffer,
            Cursor_Name
            & " := "
            & Apply_Name_Replacements
                (Render_Expr
                   (Unit,
                    Document,
                    Recursive_Call.Args (Recursive_Call.Args.First_Index),
                    State),
                 From_Names,
                 To_Names)
            & ";",
            3);
         Append_Line (Buffer, "end loop;", 2);
         Append_Line (Buffer, "return " & SU.To_String (Final_Return_Image) & ";", 2);
         return True;
      end Render_Structural_Accumulator;
   begin
      if Render_Structural_Observer then
         return True;
      end if;

      return Render_Structural_Accumulator;
   end Render_Structural_Traversal_Subprogram_Body;
   function Render_Subprogram_Aspects
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Bronze     : MB.Bronze_Result;
      State      : in out Emit_State) return String
     is
      Summary : constant MB.Graph_Summary :=
        Find_Graph_Summary (Bronze, FT.To_String (Subprogram.Name));
      Uses_Structural_Traversal : constant Boolean :=
        Uses_Structural_Traversal_Lowering (Subprogram);
      Global_Image  : constant String :=
        Render_Global_Aspect (Unit, Subprogram, Summary, Bronze);
      Depends_Image : constant String :=
        Render_Depends_Aspect (Unit, Subprogram, Summary, Bronze);
      Pre_Image : constant String :=
        Render_Access_Param_Precondition (Unit, Document, Subprogram, State);
      Access_Post_Image : constant String :=
        Render_Access_Param_Postcondition (Unit, Document, Subprogram, State);
      Inferred_Post_Image : constant String :=
        Render_Inferred_Result_Postcondition (Unit, Document, Subprogram, State);
      --  TODO: access postconditions reject Stmt_If bodies today. Keep this
      --  deterministic composition path for when that restriction is lifted.
      Post_Image : constant String :=
        (if Inferred_Post_Image'Length > 0 and then Access_Post_Image'Length > 0
         then Inferred_Post_Image & " and then " & Access_Post_Image
         elsif Inferred_Post_Image'Length > 0
         then Inferred_Post_Image
         else Access_Post_Image);
      Structural_Pre_Image : constant String :=
        (if Uses_Structural_Traversal and then Subprogram.Params.Length >= 3
         then
           Structural_Accumulator_Count_Total_Bound
             (Unit,
              Document,
              Subprogram,
              Ada_Safe_Name
                (FT.To_String
                   (Subprogram.Params (Subprogram.Params.First_Index + 1).Name)),
              Ada_Safe_Name
                (FT.To_String
                   (Subprogram.Params (Subprogram.Params.First_Index + 2).Name)),
              State)
         else "");
      Local_Names : FT.UString_Vectors.Vector;
      function Recursive_Variant_Image return String;
      Result : SU.Unbounded_String;
      Has_Aspect : Boolean := False;

      procedure Append_Aspect (Text : String) is
      begin
         if not Has_Aspect then
            Result := Result & SU.To_Unbounded_String (" with " & Text);
            Has_Aspect := True;
         else
            Result :=
              Result
              & SU.To_Unbounded_String
                  ("," & ASCII.LF
                   & Indentation (4)
                   & Text);
         end if;
      end Append_Aspect;

      function Recursive_Variant_Image return String is
         Subprogram_Name : constant String :=
           FT.Lowercase (FT.To_String (Subprogram.Name));

         function Variant_From_Expr (Expr : CM.Expr_Access) return String;
         function Variant_From_Statements
           (Statements : CM.Statement_Access_Vectors.Vector) return String;

         function Variant_From_Expr (Expr : CM.Expr_Access) return String is
            Result : constant String := "";
         begin
            if Expr = null then
               return "";
            end if;

            case Expr.Kind is
               when CM.Expr_Call =>
                  if Expr.Callee /= null
                    and then FT.Lowercase (CM.Flatten_Name (Expr.Callee)) = Subprogram_Name
                  then
                     for Index in Subprogram.Params.First_Index .. Subprogram.Params.Last_Index loop
                        exit when Expr.Args.Is_Empty or else Index > Expr.Args.Last_Index;

                        declare
                           Param      : constant CM.Symbol := Subprogram.Params (Index);
                           Mode       : constant String := FT.Lowercase (FT.To_String (Param.Mode));
                           Param_Name : constant String := FT.To_String (Param.Name);
                           Root       : constant String := Root_Name (Expr.Args (Index));
                        begin
                           if Param_Name'Length > 0
                             and then Root = Param_Name
                             and then Is_Owner_Access (Param.Type_Info)
                             and then Mode /= "mut"
                             and then Mode /= "in out"
                             and then Mode /= "out"
                           then
                              return "Structural => " & Param_Name;
                           end if;
                        end;
                     end loop;
                  end if;

                  declare
                     Callee_Result : constant String := Variant_From_Expr (Expr.Callee);
                  begin
                     if Callee_Result'Length > 0 then
                        return Callee_Result;
                     end if;
                  end;

                  if not Expr.Args.Is_Empty then
                     for Arg of Expr.Args loop
                        declare
                           Arg_Result : constant String := Variant_From_Expr (Arg);
                        begin
                           if Arg_Result'Length > 0 then
                              return Arg_Result;
                           end if;
                        end;
                     end loop;
                  end if;
               when CM.Expr_Select =>
                  return Variant_From_Expr (Expr.Prefix);
               when CM.Expr_Apply
                  | CM.Expr_Resolved_Index
                  | CM.Expr_Tuple
                  | CM.Expr_Array_Literal =>
                  if not Expr.Args.Is_Empty then
                     for Arg of Expr.Args loop
                        declare
                           Arg_Result : constant String := Variant_From_Expr (Arg);
                        begin
                           if Arg_Result'Length > 0 then
                              return Arg_Result;
                           end if;
                        end;
                     end loop;
                  end if;
               when CM.Expr_Conversion
                  | CM.Expr_Annotated
                  | CM.Expr_Unary =>
                  return Variant_From_Expr (Expr.Inner);
               when CM.Expr_Aggregate =>
                  for Field of Expr.Fields loop
                     declare
                        Field_Result : constant String := Variant_From_Expr (Field.Expr);
                     begin
                        if Field_Result'Length > 0 then
                           return Field_Result;
                        end if;
                     end;
                  end loop;
               when CM.Expr_Binary =>
                  declare
                     Left_Result : constant String := Variant_From_Expr (Expr.Left);
                  begin
                     if Left_Result'Length > 0 then
                        return Left_Result;
                     end if;
                  end;
                  return Variant_From_Expr (Expr.Right);
               when others =>
                  null;
            end case;

            return Result;
         end Variant_From_Expr;

         function Variant_From_Statements
           (Statements : CM.Statement_Access_Vectors.Vector) return String
         is
         begin
            for Item of Statements loop
               if Item = null then
                  null;
               else
                  case Item.Kind is
                     when CM.Stmt_Object_Decl =>
                        if Item.Decl.Has_Initializer then
                           declare
                              Initializer_Result : constant String :=
                                Variant_From_Expr (Item.Decl.Initializer);
                           begin
                              if Initializer_Result'Length > 0 then
                                 return Initializer_Result;
                              end if;
                           end;
                        end if;
                     when CM.Stmt_Destructure_Decl =>
                        if Item.Destructure.Has_Initializer then
                           declare
                              Initializer_Result : constant String :=
                                Variant_From_Expr (Item.Destructure.Initializer);
                           begin
                              if Initializer_Result'Length > 0 then
                                 return Initializer_Result;
                              end if;
                           end;
                        end if;
                     when CM.Stmt_Assign =>
                        declare
                           Value_Result : constant String := Variant_From_Expr (Item.Value);
                        begin
                           if Value_Result'Length > 0 then
                              return Value_Result;
                           end if;
                        end;
                     when CM.Stmt_Call | CM.Stmt_Return | CM.Stmt_Send | CM.Stmt_Delay =>
                        declare
                           Call_Result : constant String := Variant_From_Expr (Item.Call);
                           Value_Result : constant String := Variant_From_Expr (Item.Value);
                        begin
                           if Call_Result'Length > 0 then
                              return Call_Result;
                           elsif Value_Result'Length > 0 then
                              return Value_Result;
                           end if;
                        end;
                     when CM.Stmt_Receive | CM.Stmt_Try_Receive =>
                        declare
                           Value_Result : constant String := Variant_From_Expr (Item.Value);
                           Success_Result : constant String := Variant_From_Expr (Item.Success_Var);
                        begin
                           if Value_Result'Length > 0 then
                              return Value_Result;
                           elsif Success_Result'Length > 0 then
                              return Success_Result;
                           end if;
                        end;
                     when CM.Stmt_Try_Send =>
                        Raise_Internal ("unreachable: try_send rejected by resolver");
                     when CM.Stmt_If =>
                        declare
                           Condition_Result : constant String :=
                             Variant_From_Expr (Item.Condition);
                        begin
                           if Condition_Result'Length > 0 then
                              return Condition_Result;
                           end if;
                        end;
                        declare
                           Then_Result : constant String :=
                             Variant_From_Statements (Item.Then_Stmts);
                        begin
                           if Then_Result'Length > 0 then
                              return Then_Result;
                           end if;
                        end;
                        for Part of Item.Elsifs loop
                           declare
                              Condition_Result : constant String :=
                                Variant_From_Expr (Part.Condition);
                           begin
                              if Condition_Result'Length > 0 then
                                 return Condition_Result;
                              end if;
                           end;
                           declare
                              Elsif_Result : constant String :=
                                Variant_From_Statements (Part.Statements);
                           begin
                              if Elsif_Result'Length > 0 then
                                 return Elsif_Result;
                              end if;
                           end;
                        end loop;
                        if Item.Has_Else then
                           declare
                              Else_Result : constant String :=
                                Variant_From_Statements (Item.Else_Stmts);
                           begin
                              if Else_Result'Length > 0 then
                                 return Else_Result;
                              end if;
                           end;
                        end if;
                     when CM.Stmt_Case =>
                        declare
                           Expr_Result : constant String :=
                             Variant_From_Expr (Item.Case_Expr);
                        begin
                           if Expr_Result'Length > 0 then
                              return Expr_Result;
                           end if;
                        end;
                        for Arm of Item.Case_Arms loop
                           declare
                              Arm_Result : constant String :=
                                Variant_From_Statements (Arm.Statements);
                           begin
                              if Arm_Result'Length > 0 then
                                 return Arm_Result;
                              end if;
                           end;
                        end loop;
                     when CM.Stmt_While =>
                        declare
                           Condition_Result : constant String :=
                             Variant_From_Expr (Item.Condition);
                        begin
                           if Condition_Result'Length > 0 then
                              return Condition_Result;
                           end if;
                        end;
                        declare
                           Body_Result : constant String :=
                             Variant_From_Statements (Item.Body_Stmts);
                        begin
                           if Body_Result'Length > 0 then
                              return Body_Result;
                           end if;
                        end;
                     when CM.Stmt_For | CM.Stmt_Loop =>
                        declare
                           Body_Result : constant String :=
                             Variant_From_Statements (Item.Body_Stmts);
                        begin
                           if Body_Result'Length > 0 then
                              return Body_Result;
                           end if;
                        end;
                     when CM.Stmt_Select =>
                        for Arm of Item.Arms loop
                           declare
                              Arm_Result : constant String :=
                                Variant_From_Statements
                                  ((case Arm.Kind is
                                     when CM.Select_Arm_Channel => Arm.Channel_Data.Statements,
                                     when CM.Select_Arm_Delay => Arm.Delay_Data.Statements,
                                     when others => CM.Statement_Access_Vectors.Empty_Vector));
                           begin
                              if Arm_Result'Length > 0 then
                                 return Arm_Result;
                              end if;
                           end;
                        end loop;
                     when others =>
                        null;
                  end case;
               end if;
            end loop;

            return "";
         end Variant_From_Statements;
      begin
         for Decl of Subprogram.Declarations loop
            for Name of Decl.Names loop
               if FT.To_String (Name)'Length > 0 then
                  Local_Names.Append (Name);
               end if;
            end loop;
         end loop;

         return Variant_From_Statements (Subprogram.Statements);
      end Recursive_Variant_Image;
   begin
      if Has_Text (Summary.Name) then
         if not Uses_Structural_Traversal then
            declare
               Variant_Image : constant String := Recursive_Variant_Image;
            begin
               if Variant_Image'Length > 0 then
                  Append_Aspect ("Subprogram_Variant => (" & Variant_Image & ")");
               end if;
            end;
         end if;

         Append_Aspect ("Global => " & Global_Image);

         if Depends_Image'Length > 0 then
            Append_Aspect ("Depends => (" & Depends_Image & ")");
         end if;
         if Pre_Image'Length > 0 or else Structural_Pre_Image'Length > 0 then
            Append_Aspect
              ("Pre => "
               & (if Pre_Image'Length > 0 and then Structural_Pre_Image'Length > 0
                  then Pre_Image & " and then " & Structural_Pre_Image
                  elsif Pre_Image'Length > 0
                  then Pre_Image
                  else Structural_Pre_Image));
         end if;
         if Post_Image'Length > 0 then
            Append_Aspect ("Post => " & Post_Image);
         end if;
      end if;

      return SU.To_String (Result);
   end Render_Subprogram_Aspects;
   function Render_Expression_Function_Image
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String
   is
      Return_Stmt : CM.Statement_Access := null;
   begin
      if not Subprogram.Has_Return_Type
        or else Uses_Structural_Traversal_Lowering (Subprogram)
        or else not Subprogram.Declarations.Is_Empty
        or else Subprogram.Statements.Length /= 1
      then
         return "";
      end if;

      for Param of Subprogram.Params loop
         declare
            Mode : constant String := FT.Lowercase (FT.To_String (Param.Mode));
         begin
            if Mode = "mut" or else Mode = "in out" or else Mode = "out" then
               return "";
            end if;
         end;
      end loop;

      Return_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
      if Return_Stmt = null
        or else Return_Stmt.Kind /= CM.Stmt_Return
        or else Return_Stmt.Value = null
      then
         return "";
      end if;

      return
        Render_Expr_For_Target_Type
          (Unit,
           Document,
           Return_Stmt.Value,
           Subprogram.Return_Type,
           State);
   end Render_Expression_Function_Image;
   procedure Render_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State)
   is
      Raw_Outer_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Non_Alias_Declarations (Subprogram.Declarations);
      Inner_Alias_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Alias_Declarations (Subprogram.Declarations);
      Structural_Traversal_Lowering : constant Boolean :=
        Uses_Structural_Traversal_Lowering (Subprogram);
      Previous_Wide_Count : constant Ada.Containers.Count_Type :=
        State.Wide_Local_Names.Length;
      Previous_Loop_Integer_Count : constant Ada.Containers.Count_Type :=
        State.Loop_Integer_Bindings.Length;
      Outer_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Effective_Subprogram_Outer_Declarations
          (Subprogram, Raw_Outer_Declarations);
      Return_Type_Image : constant String :=
        (if Subprogram.Has_Return_Type then Render_Type_Name (Subprogram.Return_Type) else "");
      Suppress_Declaration_Warnings : constant Boolean :=
        not Structural_Traversal_Lowering and then not Outer_Declarations.Is_Empty;

      procedure Bind_Loop_Integer_Declaration
        (Decl : CM.Resolved_Object_Decl)
      is
         Static_Value : Long_Long_Integer := 0;
      begin
         if Decl.Has_Initializer
           and then Decl.Initializer /= null
           and then Is_Integer_Type (Unit, Document, Decl.Type_Info)
           and then Try_Tracked_Static_Integer_Value
             (State, Decl.Initializer, Static_Value)
         then
            for Name of Decl.Names loop
               Bind_Loop_Integer (State, FT.To_String (Name), Static_Value);
            end loop;
         end if;
      end Bind_Loop_Integer_Declaration;
   begin
      Collect_Wide_Locals
        (Unit, Document, State, Subprogram.Declarations, Subprogram.Statements);
      Push_Type_Binding_Frame (State);
      Register_Param_Type_Bindings (State, Subprogram.Params);
      Register_Type_Bindings (State, Outer_Declarations);
      Push_Cleanup_Frame (State);
      Register_Cleanup_Items (State, Outer_Declarations);
      Append_Line
        (Buffer,
         Render_Ada_Subprogram_Keyword (Subprogram)
         & " "
         & FT.To_String (Subprogram.Name)
         & Render_Subprogram_Params (Unit, Document, Subprogram.Params)
         & Render_Subprogram_Return (Unit, Document, Subprogram)
         & " is",
         1);
      if Structural_Traversal_Lowering then
         if not Render_Structural_Traversal_Subprogram_Body
           (Buffer, Unit, Document, Subprogram, State)
         then
            Raise_Internal
              ("structural traversal lowering matched a subprogram that could not be rendered");
         end if;
         Append_Line (Buffer, "end " & FT.To_String (Subprogram.Name) & ";", 1);
         Append_Line (Buffer);
         Pop_Cleanup_Frame (State);
         Pop_Type_Binding_Frame (State);
         Restore_Loop_Integer_Bindings (State, Previous_Loop_Integer_Count);
         Restore_Wide_Names (State, Previous_Wide_Count);
         return;
      end if;
      if Suppress_Declaration_Warnings then
         Append_Initialization_Warning_Suppression (Buffer, 2);
      end if;
      for Decl of Outer_Declarations loop
         Append_Line
           (Buffer,
             Render_Object_Decl_Text
               (Unit, Document, State, Decl, Local_Context => True),
            2);
         Bind_Loop_Integer_Declaration (Decl);
      end loop;
      if Suppress_Declaration_Warnings then
         Append_Initialization_Warning_Restore (Buffer, 2);
      end if;
      Append_Line (Buffer, "begin", 1);
      Render_In_Out_Param_Stabilizers (Buffer, Subprogram, 2);
      if not Inner_Alias_Declarations.Is_Empty then
         Push_Type_Binding_Frame (State);
         Register_Type_Bindings (State, Inner_Alias_Declarations);
         Append_Line (Buffer, "declare", 2);
         Render_Block_Declarations
           (Buffer, Unit, Document, Inner_Alias_Declarations, State, 3);
         Append_Line (Buffer, "begin", 2);
         Render_Required_Statement_Suite
           (Buffer,
            Unit,
            Document,
            Subprogram.Statements,
            State,
            3,
            Return_Type_Image);
         Append_Line (Buffer, "end;", 2);
         Pop_Type_Binding_Frame (State);
      else
         Render_Required_Statement_Suite
           (Buffer,
            Unit,
            Document,
            Subprogram.Statements,
            State,
            2,
            Return_Type_Image);
      end if;
      if Statements_Fall_Through (Subprogram.Statements) then
         Render_Cleanup (Buffer, Outer_Declarations, 2);
      end if;
      Append_Line (Buffer, "end " & FT.To_String (Subprogram.Name) & ";", 1);
      Append_Line (Buffer);
      Pop_Cleanup_Frame (State);
      Pop_Type_Binding_Frame (State);
      Restore_Loop_Integer_Bindings (State, Previous_Loop_Integer_Count);
      Restore_Wide_Names (State, Previous_Wide_Count);
   end Render_Subprogram_Body;
   procedure Render_Task_Body
     (Buffer    : in out SU.Unbounded_String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Task_Item : CM.Resolved_Task;
      State     : in out Emit_State)
   is
      Previous_Wide_Count : constant Ada.Containers.Count_Type :=
        State.Wide_Local_Names.Length;
      Previous_Task_Body_Depth : constant Natural := State.Task_Body_Depth;
   begin
      Collect_Wide_Locals
        (Unit, Document, State, Task_Item.Declarations, Task_Item.Statements);
      Push_Type_Binding_Frame (State);
      Register_Type_Bindings (State, Task_Item.Declarations);
      Append_Line
        (Buffer,
         "task body "
         & FT.To_String (Task_Item.Name)
         & " is",
         1);
      if not Task_Item.Declarations.Is_Empty then
         Append_Initialization_Warning_Suppression (Buffer, 2);
      end if;
      for Decl of Task_Item.Declarations loop
         Append_Line
           (Buffer,
            Render_Object_Decl_Text (Unit, Document, State, Decl, Local_Context => True),
            2);
      end loop;
      if not Task_Item.Declarations.Is_Empty then
         Append_Initialization_Warning_Restore (Buffer, 2);
      end if;
      Append_Line (Buffer, "begin", 1);
      State.Task_Body_Depth := Previous_Task_Body_Depth + 1;
      Render_Required_Statement_Suite
        (Buffer, Unit, Document, Task_Item.Statements, State, 2, "");
      State.Task_Body_Depth := Previous_Task_Body_Depth;
      if Statements_Fall_Through (Task_Item.Statements) then
         Render_Cleanup (Buffer, Task_Item.Declarations, 2);
      end if;
      Append_Line (Buffer, "end " & FT.To_String (Task_Item.Name) & ";", 1);
      Append_Line (Buffer);
      Pop_Type_Binding_Frame (State);
      State.Task_Body_Depth := Previous_Task_Body_Depth;
      Restore_Wide_Names (State, Previous_Wide_Count);
   end Render_Task_Body;
end Safe_Frontend.Ada_Emit.Proofs;
